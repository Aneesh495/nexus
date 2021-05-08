**
** Unit tests for Raft RPC message definitions and binary serialization.
**
class RaftMessagesTest : Test
{
  Void testRequestVoteRoundtrip()
  {
    cand := NodeId("candidate-1:8001")
    args := RequestVoteArgs(5, cand, 42, 4, true)

    verifyEq(args.term, 5)
    verifyEq(args.candidateId, cand)
    verifyEq(args.lastLogIndex, 42)
    verifyEq(args.lastLogTerm, 4)
    verifyTrue(args.isPreVote)

    encoded := RaftMessageCodec.encodeRequestVote(args)
    decoded := RaftMessageCodec.decodeRequestVote(encoded)

    verifyEq(decoded.term, 5)
    verifyEq(decoded.candidateId, cand)
    verifyEq(decoded.lastLogIndex, 42)
    verifyEq(decoded.lastLogTerm, 4)
    verifyTrue(decoded.isPreVote)
  }

  Void testAppendEntriesAndReply()
  {
    leader := NodeId("leader:8000")
    follower := NodeId("follower:8001")

    // Heartbeat args
    hbArgs := AppendEntriesArgs(3, leader, 10, 2, RaftLogEntry[,], 9)
    verifyTrue(hbArgs.isHeartbeat)
    verifyEq(hbArgs.entries.size, 0)

    // With entries
    entries := [RaftLogEntry(11, 3, RaftEntryType.command, "set k v")]
    aeArgs := AppendEntriesArgs(3, leader, 10, 2, entries, 9)
    verifyFalse(aeArgs.isHeartbeat)
    verifyEq(aeArgs.entries.size, 1)

    // Reply encode/decode roundtrip
    reply := AppendEntriesReply(3, true, follower, 11, 0)
    verifyEq(reply.term, 3)
    verifyTrue(reply.success)
    verifyEq(reply.followerId, follower)
    verifyEq(reply.matchIndex, 11)

    encoded := RaftMessageCodec.encodeAppendEntriesReply(reply)
    decoded := RaftMessageCodec.decodeAppendEntriesReply(encoded)

    verifyEq(decoded.term, 3)
    verifyTrue(decoded.success)
    verifyEq(decoded.followerId, follower)
    verifyEq(decoded.matchIndex, 11)
    verifyEq(decoded.conflictHintIndex, 0)
  }

  Void testSnapshotAndReadIndexMessages()
  {
    leader := NodeId("leader:8000")
    snapArgs := InstallSnapshotArgs(4, leader, 50, 3, 0, "snap-payload-bytes", true)
    verifyEq(snapArgs.lastIncludedIndex, 50)
    verifyEq(snapArgs.lastIncludedTerm, 3)
    verifyTrue(snapArgs.done)

    follower := NodeId("follower:8002")
    snapReply := InstallSnapshotReply(4, follower)
    verifyEq(snapReply.term, 4)
    verifyEq(snapReply.followerId, follower)

    readReq := ReadIndexArgs(999, follower)
    verifyEq(readReq.reqId, 999)
    verifyEq(readReq.requesterId, follower)

    readReply := ReadIndexReply(999, 52, true)
    verifyEq(readReply.reqId, 999)
    verifyEq(readReply.readIndex, 52)
    verifyTrue(readReply.success)
  }
}
