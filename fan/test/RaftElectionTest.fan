**
** Unit tests for Raft leader elections, randomized timeouts, and vote granting.
**
class RaftElectionTest : Test
{
  Void testSingleNodeElection()
  {
    selfId := NodeId("node-1:8000")
    sm := RaftStateMachine(selfId, NodeId[,])

    verifyEq(sm.role, RaftRole.follower)
    verifyEq(sm.currentTerm, 0)

    // Trigger election
    sm.startElection(1000)

    // Single-node immediately becomes leader in term 1
    verifyEq(sm.role, RaftRole.leader)
    verifyEq(sm.currentTerm, 1)
    verifyEq(sm.leaderId, selfId)
    // Log contains initial noop entry at index 1
    verifyEq(sm.log.lastIndex, 1)
    verifyEq(sm.log.entryAt(1).type, RaftEntryType.noop)
  }

  Void testThreeNodeElectionQuorum()
  {
    n1 := NodeId("node-1:8001")
    n2 := NodeId("node-2:8002")
    n3 := NodeId("node-3:8003")

    sm1 := RaftStateMachine(n1, [n2, n3])
    verifyEq(sm1.quorumSize, 2)

    // Start election on node 1
    requests := sm1.startElection(1000)
    verifyEq(sm1.role, RaftRole.candidate)
    verifyEq(sm1.currentTerm, 1)
    verifyEq(requests.size, 2)
    verifyEq(requests[0].candidateId, n1)

    // Peer 2 grants vote
    reply2 := RequestVoteReply(1, true, n2)
    becameLeader := sm1.handleRequestVoteReply(reply2)

    verifyTrue(becameLeader)
    verifyEq(sm1.role, RaftRole.leader)
    verifyEq(sm1.leaderId, n1)
    verifyEq(sm1.log.lastIndex, 1) // noop committed
  }

  Void testVoteGrantingAndRejectionRules()
  {
    n1 := NodeId("node-1:8001")
    n2 := NodeId("node-2:8002")
    n3 := NodeId("node-3:8003")

    sm2 := RaftStateMachine(n2, [n1, n3])

    // Candidate n1 with lower term (0 < 1) rejected
    sm2.currentTerm = 1
    r1 := sm2.handleRequestVote(RequestVoteArgs(0, n1, 0, 0))
    verifyFalse(r1.voteGranted)

    // Candidate n1 with higher term (2 > 1) granted
    r2 := sm2.handleRequestVote(RequestVoteArgs(2, n1, 0, 0))
    verifyTrue(r2.voteGranted)
    verifyEq(sm2.currentTerm, 2)
    verifyEq(sm2.votedFor, n1)

    // Second candidate n3 in same term 2 rejected because n2 already voted for n1
    r3 := sm2.handleRequestVote(RequestVoteArgs(2, n3, 0, 0))
    verifyFalse(r3.voteGranted)
  }

  Void testCandidateLogCompletenessCheck()
  {
    n1 := NodeId("node-1:8001")
    n2 := NodeId("node-2:8002")

    sm2 := RaftStateMachine(n2, [n1])
    // Node 2 has log up to index 5 in term 2
    for (i := 1; i <= 5; ++i)
    {
      sm2.log.append(RaftLogEntry(i, 2, RaftEntryType.command, "x"))
    }
    sm2.currentTerm = 2

    // Candidate 1 with lastLogTerm 1 (stale term) must be denied
    r1 := sm2.handleRequestVote(RequestVoteArgs(3, n1, 10, 1))
    verifyFalse(r1.voteGranted)

    // Candidate 1 with lastLogTerm 2 but index 4 (< index 5) must be denied
    r2 := sm2.handleRequestVote(RequestVoteArgs(3, n1, 4, 2))
    verifyFalse(r2.voteGranted)

    // Candidate 1 with lastLogTerm 2 and index 5 (matching) granted
    r3 := sm2.handleRequestVote(RequestVoteArgs(3, n1, 5, 2))
    verifyTrue(r3.voteGranted)
  }

  Void testStepDownOnHigherTerm()
  {
    n1 := NodeId("node-1:8001")
    n2 := NodeId("node-2:8002")
    n3 := NodeId("node-3:8003")

    sm1 := RaftStateMachine(n1, [n2, n3])
    sm1.startElection(1000)
    sm1.handleRequestVoteReply(RequestVoteReply(1, true, n2))
    verifyEq(sm1.role, RaftRole.leader)

    // Discover peer reply with term 5
    sm1.handleAppendEntriesReply(n2, AppendEntriesReply(5, false, n2, 0))
    verifyEq(sm1.role, RaftRole.follower)
    verifyEq(sm1.currentTerm, 5)
    verifyNull(sm1.leaderId)
  }
}
