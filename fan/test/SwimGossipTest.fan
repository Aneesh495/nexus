**
** Unit tests for SwimGossip membership, failure detection, and refutation.
**
class SwimGossipTest : Test
{
  Void testMembershipAndProbeSelection()
  {
    local := NodeId("node-local:8000")
    gossip := SwimGossip(local)

    verifyEq(gossip.activeCount, 1)
    verifyEq(gossip.selfNode, local)
    verifyEq(gossip.selfIncarnation, 0)

    n1 := NodeId("node-1:8001")
    n2 := NodeId("node-2:8002")
    n3 := NodeId("node-3:8003")

    gossip.addMember(n1)
    gossip.addMember(n2)
    gossip.addMember(n3)

    verifyEq(gossip.activeCount, 4)

    target := gossip.selectPingTarget
    verifyNotNull(target)
    verifyTrue(target != local)

    proxies := gossip.selectIndirectProxies(n1, 2)
    verifyEq(proxies.size, 2)
    verifyFalse(proxies.contains(local))
    verifyFalse(proxies.contains(n1))
  }

  Void testSuspicionAndTimeoutToDead()
  {
    local := NodeId("local:8000")
    gossip := SwimGossip(local, 3000)

    n1 := NodeId("remote-1:8001")
    gossip.addMember(n1)

    t0 := 10_000
    // Probe failure occurs: mark as suspect
    gossip.suspectNode(n1, t0)
    m1 := gossip.getMember(n1)
    verifyEq(m1.state, SwimState.suspect)

    // At t0 + 1000ms, not timed out yet
    dead1 := gossip.sweepSuspects(t0 + 1000)
    verifyTrue(dead1.isEmpty)
    verifyEq(gossip.getMember(n1).state, SwimState.suspect)

    // At t0 + 3500ms, suspicion timeout expired: marked dead
    dead2 := gossip.sweepSuspects(t0 + 3500)
    verifyEq(dead2.size, 1)
    verifyEq(dead2.first, n1)
    verifyEq(gossip.getMember(n1).state, SwimState.dead)
    verifyEq(gossip.activeCount, 1) // only local node active
  }

  Void testLocalRefutation()
  {
    local := NodeId("local:8000")
    gossip := SwimGossip(local)
    verifyEq(gossip.selfIncarnation, 0)

    // Another node suspects local node at incarnation 0
    suspectLocalEvt := SwimGossipEvent(local, 0, SwimState.suspect)
    updated := gossip.processGossipEvent(suspectLocalEvt, 1000)

    verifyTrue(updated)
    // Local node must refute by advancing its incarnation to 1 and staying alive
    verifyEq(gossip.selfIncarnation, 1)
    selfMember := gossip.getMember(local)
    verifyEq(selfMember.state, SwimState.alive)
    verifyEq(selfMember.incarnation, 1)

    // Verify refutation gossip event is queued in outbound buffer
    events := gossip.drainGossip(10)
    verifyTrue(events.any |e| { e.subject == local && e.incarnation == 1 && e.state == SwimState.alive })
  }

  Void testIncarnationPrecedenceRules()
  {
    local := NodeId("local:8000")
    gossip := SwimGossip(local)
    peer := NodeId("peer:8001")

    // Event 1: peer is alive at incarnation 1
    gossip.processGossipEvent(SwimGossipEvent(peer, 1, SwimState.alive), 100)
    verifyEq(gossip.getMember(peer).incarnation, 1)
    verifyEq(gossip.getMember(peer).state, SwimState.alive)

    // Event 2: peer is suspected at same incarnation (1) -> Suspect overrides Alive
    gossip.processGossipEvent(SwimGossipEvent(peer, 1, SwimState.suspect), 200)
    verifyEq(gossip.getMember(peer).state, SwimState.suspect)

    // Event 3: stale alive at incarnation 0 -> ignored
    gossip.processGossipEvent(SwimGossipEvent(peer, 0, SwimState.alive), 300)
    verifyEq(gossip.getMember(peer).state, SwimState.suspect)
    verifyEq(gossip.getMember(peer).incarnation, 1)

    // Event 4: peer refutes at incarnation 2 -> higher incarnation wins
    gossip.processGossipEvent(SwimGossipEvent(peer, 2, SwimState.alive), 400)
    verifyEq(gossip.getMember(peer).state, SwimState.alive)
    verifyEq(gossip.getMember(peer).incarnation, 2)
  }
}
