**
** Unit tests for Raft log replication, quorum commit advancement, and ReadIndex.
**
class RaftReplicationTest : Test
{
  Void testEndToEndReplicationPipeline()
  {
    leaderId := NodeId("leader:8000")
    followerId := NodeId("follower:8001")
    peer2Id := NodeId("peer2:8002")

    leader := RaftStateMachine(leaderId, [followerId, peer2Id])
    follower := RaftStateMachine(followerId, [leaderId, peer2Id])

    // Establish leadership on leader
    leader.startElection(1000)
    leader.handleRequestVoteReply(RequestVoteReply(1, true, followerId))
    verifyEq(leader.role, RaftRole.leader)
    verifyEq(leader.commitIndex, 0)
    // Initial noop at index 1
    verifyEq(leader.log.lastIndex, 1)

    // Leader proposes user command
    cmd1 := leader.propose("SET user:1 Jane")
    verifyNotNull(cmd1)
    verifyEq(cmd1.index, 2)
    verifyEq(cmd1.payload, "SET user:1 Jane")
    verifyEq(leader.log.lastIndex, 2)

    // Generate replication message for follower
    aeMsg := leader.generateReplication(followerId)
    verifyNotNull(aeMsg)
    verifyEq(aeMsg.entries.size, 2) // noop at idx 1, cmd at idx 2
    verifyEq(aeMsg.prevLogIndex, 0)

    // Follower ingests replication message
    reply := follower.handleAppendEntries(aeMsg)
    verifyTrue(reply.success)
    verifyEq(reply.matchIndex, 2)
    verifyEq(follower.log.lastIndex, 2)
    verifyEq(follower.log.entryAt(2).payload, "SET user:1 Jane")

    // Leader processes follower reply -> advances commitIndex
    commitAdvanced := leader.handleAppendEntriesReply(followerId, reply)
    verifyTrue(commitAdvanced)
    verifyEq(leader.commitIndex, 2)

    // Leader applies committed entries
    applied := leader.applyCommittedEntries
    verifyEq(applied.size, 2)
    verifyEq(applied[0].type, RaftEntryType.noop)
    verifyEq(applied[1].payload, "SET user:1 Jane")
    verifyEq(leader.lastApplied, 2)
  }

  Void testLogDivergenceReconciliation()
  {
    leaderId := NodeId("leader:8000")
    followerId := NodeId("follower:8001")

    leader := RaftStateMachine(leaderId, [followerId])
    follower := RaftStateMachine(followerId, [leaderId])

    // Establish term 2 on leader
    leader.currentTerm = 2
    leader.role = RaftRole.leader
    leader.log.append(RaftLogEntry(1, 1, RaftEntryType.command, "cmd-1"))
    leader.log.append(RaftLogEntry(2, 2, RaftEntryType.command, "cmd-2-leader"))
    leader.nextIndexMap[followerId.id] = 3

    // Follower has conflicting entry at index 2 from old term 1
    follower.currentTerm = 2
    follower.log.append(RaftLogEntry(1, 1, RaftEntryType.command, "cmd-1"))
    follower.log.append(RaftLogEntry(2, 1, RaftEntryType.command, "cmd-2-stale"))

    // Leader attempts to send index 3 (empty entries, prevLogIndex 2, term 2)
    ae := AppendEntriesArgs(2, leaderId, 2, 2, RaftLogEntry[,], 1)
    reply := follower.handleAppendEntries(ae)

    // Follower rejects because at index 2 its term is 1, not 2
    verifyFalse(reply.success)

    // Leader handles rejection and backs up nextIndex
    leader.handleAppendEntriesReply(followerId, reply)
    verifyTrue(leader.nextIndexMap[followerId.id] <= 2)

    // Leader re-generates replication from backed-up index
    aeRetry := leader.generateReplication(followerId)
    verifyNotNull(aeRetry)
    verifyEq(aeRetry.prevLogIndex, 0)
    verifyEq(aeRetry.prevLogTerm, 0)

    // Follower accepts retry, truncating its stale index 2 and adopting leader index 2
    retryReply := follower.handleAppendEntries(aeRetry)
    verifyTrue(retryReply.success)
    verifyEq(follower.log.lastIndex, 2)
    verifyEq(follower.log.entryAt(2).payload, "cmd-2-leader")
  }

  Void testLinearizableReadIndex()
  {
    leaderId := NodeId("leader:8000")
    f1 := NodeId("f1:8001")
    f2 := NodeId("f2:8002")

    leader := RaftStateMachine(leaderId, [f1, f2])
    leader.startElection(1000)
    leader.handleRequestVoteReply(RequestVoteReply(1, true, f1))
    verifyEq(leader.role, RaftRole.leader)

    // Non-leader rejects ReadIndex
    follower := RaftStateMachine(f1, [leaderId, f2])
    verifyEq(follower.startReadIndex(100), -1)

    // Set commitIndex on leader
    leader.commitIndex = 42

    // Leader initiates ReadIndex request 101
    rIdx := leader.startReadIndex(101)
    verifyEq(rIdx, 42)
    // Not yet fulfilled (only self ack so far, quorum = 2)
    verifyEq(leader.getReadIndex(101), -1)

    // Peer 1 acknowledges heartbeat
    fulfilled := leader.recordReadHeartbeatAck(101, f1)
    verifyTrue(fulfilled)
    verifyEq(leader.getReadIndex(101), 42)
  }
}
