**
** SwimState: Node lifecycle status within the SWIM gossip protocol.
**
enum class SwimState
{
  alive,
  suspect,
  dead
}

**
** SwimMember: Immutably captures member incarnation, state, and address.
**
const class SwimMember
{
  const NodeId node
  const Int incarnation
  const SwimState state
  const Int lastUpdatedMillis

  new make(NodeId node, Int incarnation, SwimState state, Int lastUpdatedMillis := DateTime.now.toJava)
  {
    this.node              = node
    this.incarnation       = incarnation
    this.state             = state
    this.lastUpdatedMillis = lastUpdatedMillis
  }

  override Str toStr()
  {
    return "${node.id}:${state.name}:inc=${incarnation}"
  }
}

**
** SwimGossipEvent: Piggybacked gossip record propagated on pings and acks.
**
const class SwimGossipEvent
{
  const NodeId subject
  const Int incarnation
  const SwimState state

  new make(NodeId subject, Int incarnation, SwimState state)
  {
    this.subject     = subject
    this.incarnation = incarnation
    this.state       = state
  }

  override Str toStr()
  {
    return "Event(${subject.id}, ${state.name}, v=${incarnation})"
  }
}

**
** SwimGossip: Decentralized failure detection and membership via SWIM protocol with suspicion mechanism.
**
** Reference:
** Das, Gupta, Motivala, "SWIM: A Robust Sub-Microsecond Cluster Membership Protocol",
** IEEE International Conference on Dependable Systems and Networks (DSN) 2002.
**
class SwimGossip
{
  private NodeId localNode
  private Int localIncarnation := 0
  private Str:SwimMember members := Str:SwimMember[:]
  private SwimGossipEvent[] gossipBuffer := SwimGossipEvent[,]
  private FastRandom rng := FastRandom(1337)
  private Int suspicionTimeoutMillis := 5000

  new make(NodeId localNode, Int suspicionTimeoutMillis := 5000)
  {
    this.localNode = localNode
    this.suspicionTimeoutMillis = suspicionTimeoutMillis
    // Local node is always initially alive at incarnation 0
    members[localNode.id] = SwimMember(localNode, 0, SwimState.alive)
  }

  **
  ** Local node identity.
  **
  NodeId selfNode() { return localNode }

  **
  ** Current local incarnation number.
  **
  Int selfIncarnation() { return localIncarnation }

  **
  ** Current known membership list.
  **
  SwimMember[] memberList() { return members.vals }

  **
  ** Lookup specific member.
  **
  SwimMember? getMember(NodeId id) { return members[id.id] }

  **
  ** Total active members (alive or suspect).
  **
  Int activeCount()
  {
    return members.vals.findAll |SwimMember m -> Bool| { m.state != SwimState.dead }.size
  }

  **
  ** Add or register a newly discovered node.
  **
  Void addMember(NodeId node, Int incarnation := 0)
  {
    if (members.containsKey(node.id)) return
    member := SwimMember(node, incarnation, SwimState.alive)
    members[node.id] = member
    enqueueGossip(SwimGossipEvent(node, incarnation, SwimState.alive))
  }

  **
  ** Select a random target node for direct ping probe (excluding self and dead nodes).
  **
  NodeId? selectPingTarget()
  {
    candidates := members.vals.findAll |SwimMember m -> Bool| { m.node != localNode && m.state != SwimState.dead }
    if (candidates.isEmpty) return null
    idx := rng.nextInt(candidates.size)
    return ((SwimMember)candidates[idx]).node
  }

  **
  ** Select k indirect proxy nodes to ping a target on our behalf.
  **
  NodeId[] selectIndirectProxies(NodeId target, Int k := 3)
  {
    candidates := members.vals.findAll |SwimMember m -> Bool| {
      m.node != localNode && m.node != target && m.state == SwimState.alive
    }
    if (candidates.isEmpty) return NodeId[,]

    // Fisher-Yates partial shuffle for k elements
    result := NodeId[,]
    shuffled := candidates.dup
    n := shuffled.size
    picks := k.min(n)
    picks.times |i|
    {
      swapIdx := rng.nextRange(i, n - 1)
      temp := shuffled[i]
      shuffled[i] = shuffled[swapIdx]
      shuffled[swapIdx] = temp
      result.add(((SwimMember)shuffled[i]).node)
    }
    return result
  }

  **
  ** Handle incoming ping or ack message containing piggybacked gossip events.
  **
  Void handleGossip(SwimGossipEvent[] events, Int nowMillis := DateTime.now.toJava)
  {
    events.each |e|
    {
      processGossipEvent(e, nowMillis)
    }
  }

  **
  ** Process a single gossip event according to SWIM suspicion state transition rules.
  **
  Bool processGossipEvent(SwimGossipEvent event, Int nowMillis := DateTime.now.toJava)
  {
    subj := event.subject

    // Rule: If someone suspects us, refute by incrementing incarnation and declaring alive
    if (subj == localNode)
    {
      if (event.state == SwimState.suspect && event.incarnation >= localIncarnation)
      {
        localIncarnation = event.incarnation + 1
        refuteEvent := SwimGossipEvent(localNode, localIncarnation, SwimState.alive)
        members[localNode.id] = SwimMember(localNode, localIncarnation, SwimState.alive, nowMillis)
        enqueueGossip(refuteEvent)
        return true
      }
      return false
    }

    current := members[subj.id]

    // New node discovered via gossip
    if (current == null)
    {
      if (event.state != SwimState.dead)
      {
        members[subj.id] = SwimMember(subj, event.incarnation, event.state, nowMillis)
        enqueueGossip(event)
        return true
      }
      return false
    }

    // Existing node update evaluation:
    // 1. Higher incarnation always wins
    // 2. Same incarnation: Suspect overrides Alive; Dead overrides Suspect and Alive
    shouldUpdate := false

    if (event.incarnation > current.incarnation)
    {
      shouldUpdate = true
    }
    else if (event.incarnation == current.incarnation)
    {
      if (current.state == SwimState.alive && event.state == SwimState.suspect)
      {
        shouldUpdate = true
      }
      else if (current.state != SwimState.dead && event.state == SwimState.dead)
      {
        shouldUpdate = true
      }
    }

    if (shouldUpdate)
    {
      members[subj.id] = SwimMember(subj, event.incarnation, event.state, nowMillis)
      enqueueGossip(event)
      return true
    }

    return false
  }

  **
  ** Mark a target node as suspect after direct and indirect probe timeouts.
  **
  Void suspectNode(NodeId target, Int nowMillis := DateTime.now.toJava)
  {
    curr := members[target.id]
    if (curr == null || curr.state == SwimState.dead) return

    evt := SwimGossipEvent(target, curr.incarnation, SwimState.suspect)
    members[target.id] = SwimMember(target, curr.incarnation, SwimState.suspect, nowMillis)
    enqueueGossip(evt)
  }

  **
  ** Confirm a target node is alive (e.g. successful probe response).
  **
  Void aliveNode(NodeId target, Int incarnation, Int nowMillis := DateTime.now.toJava)
  {
    curr := members[target.id]
    if (curr == null || incarnation > curr.incarnation || (incarnation == curr.incarnation && curr.state == SwimState.suspect))
    {
      members[target.id] = SwimMember(target, incarnation, SwimState.alive, nowMillis)
      enqueueGossip(SwimGossipEvent(target, incarnation, SwimState.alive))
    }
  }

  **
  ** Periodic sweep to transition timed-out suspect nodes into dead state.
  **
  NodeId[] sweepSuspects(Int nowMillis := DateTime.now.toJava)
  {
    deadNodes := NodeId[,]
    members.vals.each |SwimMember m|
    {
      if (m.state == SwimState.suspect && m.node != localNode)
      {
        if (nowMillis - m.lastUpdatedMillis >= suspicionTimeoutMillis)
        {
          members[m.node.id] = SwimMember(m.node, m.incarnation, SwimState.dead, nowMillis)
          enqueueGossip(SwimGossipEvent(m.node, m.incarnation, SwimState.dead))
          deadNodes.add(m.node)
        }
      }
    }
    return deadNodes
  }

  **
  ** Drain recent gossip events to piggyback on outgoing probe messages.
  **
  SwimGossipEvent[] drainGossip(Int maxCount := 8)
  {
    if (gossipBuffer.isEmpty) return SwimGossipEvent[,]
    takeCount := maxCount.min(gossipBuffer.size)
    drained := gossipBuffer[0..<takeCount]
    gossipBuffer.removeRange(0..<takeCount)
    return drained
  }

  private Void enqueueGossip(SwimGossipEvent evt)
  {
    if (gossipBuffer.size < 256)
    {
      gossipBuffer.add(evt)
    }
  }
}
