using concurrent

**
** TopologyMessageType: Enumeration of internal cluster actor messages.
**
enum class TopologyMessageType
{
  join,
  leave,
  heartbeat,
  tick,
  query_route,
  query_snapshot
}

**
** TopologyMessage: Immutable message envelope passed to ClusterTopologyActor.
**
const class TopologyMessage
{
  const TopologyMessageType type
  const NodeId? nodeId
  const NodeStatus? status
  const Int timestamp
  const Str? key

  new makeJoin(NodeId nodeId, NodeStatus status := NodeStatus.active)
  {
    this.type      = TopologyMessageType.join
    this.nodeId    = nodeId
    this.status    = status
    this.timestamp = DateTime.now.toJava
  }

  new makeLeave(NodeId nodeId)
  {
    this.type      = TopologyMessageType.leave
    this.nodeId    = nodeId
    this.timestamp = DateTime.now.toJava
  }

  new makeHeartbeat(NodeId nodeId, Int timestamp := DateTime.now.toJava)
  {
    this.type      = TopologyMessageType.heartbeat
    this.nodeId    = nodeId
    this.timestamp = timestamp
  }

  new makeTick(Int timestamp := DateTime.now.toJava)
  {
    this.type      = TopologyMessageType.tick
    this.timestamp = timestamp
  }

  new makeQueryRoute(Str key)
  {
    this.type      = TopologyMessageType.query_route
    this.key       = key
    this.timestamp = DateTime.now.toJava
  }

  new makeQuerySnapshot()
  {
    this.type      = TopologyMessageType.query_snapshot
    this.timestamp = DateTime.now.toJava
  }
}

**
** ClusterTopologySnapshot: Point-in-time immutable view of cluster state.
**
const class ClusterTopologySnapshot
{
  const Int epoch
  const NodeId[] nodes
  const Int partitionCount
  const Int replicaFactor

  new make(Int epoch, NodeId[] nodes, Int partitionCount, Int replicaFactor)
  {
    this.epoch          = epoch
    this.nodes          = nodes.toImmutable
    this.partitionCount = partitionCount
    this.replicaFactor  = replicaFactor
  }
}

**
** ClusterTopologyState: Mutable internal state held exclusively inside actor thread.
**
internal class ClusterTopologyState
{
  NodeId localNode
  Int partitionCount
  Int replicaFactor
  Int vnodesPerNode
  Int epoch := 0

  Str:ClusterNode nodeMap := Str:ClusterNode[:]
  HashRing ring
  PartitionTable table
  PhiFailureDetector failureDetector
  SwimGossip gossip
  PartitionRebalancer rebalancer

  new make(NodeId localNode, Int partitionCount, Int replicaFactor, Int vnodesPerNode)
  {
    this.localNode       = localNode
    this.partitionCount  = partitionCount
    this.replicaFactor   = replicaFactor
    this.vnodesPerNode   = vnodesPerNode

    this.ring            = HashRing(vnodesPerNode)
    this.failureDetector = PhiFailureDetector(8.0f)
    this.gossip          = SwimGossip(localNode)
    this.rebalancer      = PartitionRebalancer(localNode)

    // Register local node initially
    localClusterNode := ClusterNode(localNode, NodeStatus.active)
    nodeMap[localNode.id] = localClusterNode
    ring.addNode(localNode)
    this.table = PartitionTable.buildFromRing(ring, partitionCount, replicaFactor, 0)
  }

  Void recomputeTopology()
  {
    epoch++
    oldTable := table
    newTable := PartitionTable.buildFromRing(ring, partitionCount, replicaFactor, epoch)
    diff := oldTable.diff(newTable)
    table = newTable
    rebalancer.planMigrations(diff, oldTable)
  }
}

**
** ClusterTopologyActor: Thread-isolated coordinator for cluster membership,
** health detection, consistent ring topology, and partition routing.
**
class ClusterTopologyActor
{
  private Actor actor

  new make(ActorPool pool, NodeId localNode, Int partitionCount := 64, Int replicaFactor := 3, Int vnodesPerNode := 128)
  {
    this.actor = Actor(pool) |Obj? msg -> Obj?| {
      state := (ClusterTopologyState?)Actor.locals["nexus.topo.state"]
      if (state == null)
      {
        state = ClusterTopologyState(localNode, partitionCount, replicaFactor, vnodesPerNode)
        Actor.locals["nexus.topo.state"] = state
      }
      return handleMessage(state, (TopologyMessage)msg)
    }
  }

  **
  ** Synchronous registration of a newly joined node.
  **
  Bool join(NodeId nodeId, NodeStatus status := NodeStatus.active)
  {
    return (Bool)actor.send(TopologyMessage.makeJoin(nodeId, status)).get
  }

  **
  ** Synchronous deregistration of a departed or failed node.
  **
  Bool leave(NodeId nodeId)
  {
    return (Bool)actor.send(TopologyMessage.makeLeave(nodeId)).get
  }

  **
  ** Record a heartbeat from a remote node.
  **
  Void heartbeat(NodeId nodeId, Int timestamp := DateTime.now.toJava)
  {
    actor.send(TopologyMessage.makeHeartbeat(nodeId, timestamp))
  }

  **
  ** Trigger periodic health check tick.
  **
  Int tick(Int timestamp := DateTime.now.toJava)
  {
    return (Int)actor.send(TopologyMessage.makeTick(timestamp)).get
  }

  **
  ** Query partition assignment for a key.
  **
  PartitionAssignment? queryRoute(Str key)
  {
    return (PartitionAssignment?)actor.send(TopologyMessage.makeQueryRoute(key)).get
  }

  **
  ** Capture point-in-time snapshot of the cluster topology.
  **
  ClusterTopologySnapshot getSnapshot()
  {
    return (ClusterTopologySnapshot)actor.send(TopologyMessage.makeQuerySnapshot()).get
  }

  internal static Obj? handleMessage(ClusterTopologyState state, TopologyMessage msg)
  {
    switch (msg.type)
    {
      case TopologyMessageType.join:
        id := msg.nodeId
        if (id == null || state.nodeMap.containsKey(id.id)) return false
        status := msg.status ?: NodeStatus.active
        node := ClusterNode(id, status)
        state.nodeMap[id.id] = node
        state.ring.addNode(id)
        state.gossip.addMember(id)
        state.recomputeTopology
        return true

      case TopologyMessageType.leave:
        id := msg.nodeId
        if (id == null || !state.nodeMap.containsKey(id.id)) return false
        state.nodeMap.remove(id.id)
        state.ring.removeNode(id)
        state.failureDetector.remove(id.id)
        state.recomputeTopology
        return true

      case TopologyMessageType.heartbeat:
        id := msg.nodeId
        if (id != null)
        {
          state.failureDetector.heartbeat(id.id, msg.timestamp)
        }
        return null

      case TopologyMessageType.tick:
        deadDetected := 0
        now := msg.timestamp
        state.nodeMap.vals.each |ClusterNode n|
        {
          if (n.id != state.localNode)
          {
            if (!state.failureDetector.isAvailable(n.id.id, now))
            {
              state.nodeMap.remove(n.id.id)
              state.ring.removeNode(n.id)
              state.failureDetector.remove(n.id.id)
              deadDetected++
            }
          }
        }
        if (deadDetected > 0)
        {
          state.recomputeTopology
        }
        return deadDetected

      case TopologyMessageType.query_route:
        key := msg.key ?: ""
        partId := state.table.getPartitionId(key)
        return state.table.getAssignment(partId)

      case TopologyMessageType.query_snapshot:
        nodeIds := state.nodeMap.vals.map |ClusterNode n -> NodeId| { n.id }
        return ClusterTopologySnapshot(
          state.epoch,
          nodeIds,
          state.partitionCount,
          state.replicaFactor
        )

      default:
        throw Err("Unknown topology message type: $msg.type")
    }
  }
}
