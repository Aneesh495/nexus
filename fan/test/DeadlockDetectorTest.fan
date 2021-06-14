class DeadlockDetectorTest : Test
{
  Void testNoCycles()
  {
    detector := DeadlockDetector(VictimPolicy.youngest)

    n1 := NodeId("node-1")
    t1 := TxId(n1, 1, 1000)
    t2 := TxId(n1, 2, 1001)
    t3 := TxId(n1, 3, 1002)

    detector.addWaitEdge(t1, t2)
    detector.addWaitEdge(t2, t3)

    verifyEq(detector.hasEdge(t1, t2), true)
    verifyEq(detector.hasEdge(t2, t3), true)
    verifyEq(detector.hasEdge(t3, t1), false)

    cycles := detector.findCycles()
    verifyEq(cycles.size, 0)

    victims := detector.resolveDeadlocks()
    verifyEq(victims.size, 0)
    verifyEq(detector.txCount, 3)
  }

  Void testSimpleTwoNodeCycle()
  {
    detector := DeadlockDetector(VictimPolicy.youngest)

    n1 := NodeId("node-1")
    t1 := TxId(n1, 1, 1000)
    t2 := TxId(n1, 1, 2000) // t2 is younger (timestamp 2000 vs 1000)

    detector.addWaitEdge(t1, t2)
    detector.addWaitEdge(t2, t1)

    cycles := detector.findCycles()
    verifyEq(cycles.size >= 1, true)

    victim := detector.selectVictim(cycles.first)
    verifyEq(victim, t2)

    victims := detector.resolveDeadlocks()
    verifyEq(victims.size, 1)
    verifyEq(victims.first, t2)

    // After resolving, graph must be acyclic
    verifyEq(detector.findCycles().size, 0)
    verifyEq(detector.hasEdge(t2, t1), false)
  }

  Void testThreeNodeCycle()
  {
    detector := DeadlockDetector(VictimPolicy.youngest)

    n1 := NodeId("node-1")
    t1 := TxId(n1, 1, 1000)
    t2 := TxId(n1, 2, 1500)
    t3 := TxId(n1, 3, 2500) // youngest

    detector.addWaitEdge(t1, t2)
    detector.addWaitEdge(t2, t3)
    detector.addWaitEdge(t3, t1)

    cycles := detector.findCycles()
    verifyEq(cycles.size >= 1, true)

    victims := detector.resolveDeadlocks()
    verifyEq(victims.size, 1)
    verifyEq(victims.first, t3)

    // Remainder is acyclic: T1 -> T2
    verifyEq(detector.findCycles().size, 0)
    verifyEq(detector.hasEdge(t1, t2), true)
  }

  Void testLeastWorkVictimPolicy()
  {
    detector := DeadlockDetector(VictimPolicy.leastWork)

    n1 := NodeId("node-1")
    t1 := TxId(n1, 1, 2500) // older
    t2 := TxId(n1, 2, 1000) // younger

    // t1 holds 10 locks, t2 holds 1 lock
    detector.registerTx(t1, 10)
    detector.registerTx(t2, 1)

    detector.addWaitEdge(t1, t2)
    detector.addWaitEdge(t2, t1)

    cycles := detector.findCycles()
    verifyEq(cycles.size >= 1, true)

    victim := detector.selectVictim(cycles.first)
    verifyEq(victim, t2) // t2 has least work (1 lock vs 10)

    victims := detector.resolveDeadlocks()
    verifyEq(victims.size, 1)
    verifyEq(victims.first, t2)
  }

  Void testEdgeRemovalAndCleanup()
  {
    detector := DeadlockDetector()

    n1 := NodeId("node-1")
    t1 := TxId(n1, 1, 100)
    t2 := TxId(n1, 2, 200)

    detector.addWaitEdge(t1, t2)
    verifyEq(detector.hasEdge(t1, t2), true)

    detector.removeWaitEdge(t1, t2)
    verifyEq(detector.hasEdge(t1, t2), false)

    detector.addWaitEdge(t1, t2)
    detector.removeTx(t2)
    verifyEq(detector.hasEdge(t1, t2), false)
    verifyEq(detector.txCount, 1)
  }
}
