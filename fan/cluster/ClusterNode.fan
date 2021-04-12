**
** Cluster member lifecycle state.
**
enum class NodeStatus
{
  joining,
  active,
  suspect,
  dead,
  leaving
}

**
** ClusterNode: Dynamic state, health telemetry, and incarnation tracking for a cluster peer.
**
class ClusterNode
{
  const NodeId id
  NodeStatus status := NodeStatus.joining
  Int incarnation := 0
  Int lastHeartbeatTime := DateTime.now.toJava
  Float cpuLoad := 0.0f
  Int heapUsedBytes := 0
  Int heapMaxBytes := 0
  Int activePartitions := 0

  **
  ** Create new cluster node descriptor.
  **
  new make(NodeId id, NodeStatus initialStatus := NodeStatus.joining)
  {
    this.id     = id
    this.status = initialStatus
  }

  **
  ** Check if the node is in active state and eligible for traffic.
  **
  Bool isAlive()
  {
    return status == NodeStatus.active || status == NodeStatus.suspect
  }

  **
  ** Check if the node is considered fully operational.
  **
  Bool isActive()
  {
    return status == NodeStatus.active
  }

  **
  ** Record heartbeat arrival to update last-seen timestamp.
  **
  This updateHeartbeat(Int nowMillis := DateTime.now.toJava)
  {
    this.lastHeartbeatTime = nowMillis
    return this
  }

  **
  ** Advance incarnation counter (used by SWIM protocol to refute false suspicion).
  **
  This advanceIncarnation()
  {
    this.incarnation++
    return this
  }

  override Str toStr()
  {
    return "ClusterNode($id, status=$status, inc=$incarnation, parts=$activePartitions)"
  }
}
