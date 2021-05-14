using concurrent

**
** Unit tests for MultiRaftGroup coordination, multiplexing, and partition store binding.
**
class MultiRaftGroupTest : Test
{
  Void testMultiPartitionLifecycle()
  {
    pool := ActorPool()
    localNode := NodeId("local:8000")
    multi := MultiRaftGroup(localNode, pool)

    verifyEq(multi.groupCount, 0)

    peer1 := NodeId("peer-1:8001")
    peer2 := NodeId("peer-2:8002")

    // Register partition 1
    store1 := PartitionStore(1)
    sm1 := multi.registerPartition(1, [peer1, peer2], store1)
    verifyEq(multi.groupCount, 1)
    verifyNotNull(multi.getGroup(1))

    // Register partition 2
    store2 := PartitionStore(2)
    sm2 := multi.registerPartition(2, [peer1], store2)
    verifyEq(multi.groupCount, 2)

    // Unregister partition 2
    multi.unregisterPartition(2)
    verifyEq(multi.groupCount, 1)
    verifyNull(multi.getGroup(2))

    pool.stop
    pool.join
  }

  Void testProposalAndStateApplication()
  {
    pool := ActorPool()
    localNode := NodeId("local:8000")
    peer1 := NodeId("peer-1:8001")

    multi := MultiRaftGroup(localNode, pool)
    store := PartitionStore(10)
    sm := multi.registerPartition(10, [peer1], store)

    // Make local node leader for partition 10
    sm.startElection(1000)
    sm.handleRequestVoteReply(RequestVoteReply(1, true, peer1))
    verifyEq(sm.role, RaftRole.leader)

    // Propose key-value pair
    entry := multi.propose(10, "sensor:temp", "24.5C", 0)
    verifyNotNull(entry)
    verifyEq(entry.payload, "PUT\tsensor:temp\t24.5C\t0")

    // Quorum replication: peer1 acks entry
    reply := AppendEntriesReply(1, true, peer1, entry.index, 0)
    sm.handleAppendEntriesReply(peer1, reply)
    verifyEq(sm.commitIndex, entry.index)

    // Apply committed entries across multi-raft group
    appliedCount := multi.applyCommitted
    verifyEq(appliedCount, 1)

    // Verify written to PartitionStore
    cacheEntry := store.get("sensor:temp")
    verifyNotNull(cacheEntry)
    verifyEq(cacheEntry.val, "24.5C")

    pool.stop
    pool.join
  }

  Void testMultiplexedRouting()
  {
    pool := ActorPool()
    localNode := NodeId("local:8000")
    peer1 := NodeId("peer-1:8001")

    multi := MultiRaftGroup(localNode, pool)
    store := PartitionStore(20)
    sm := multi.registerPartition(20, [peer1], store)

    // Route RequestVote to partition 20
    voteReq := RequestVoteArgs(2, peer1, 0, 0)
    voteReply := multi.routeRequestVote(20, voteReq)
    verifyNotNull(voteReply)
    verifyTrue(voteReply.voteGranted)

    // Route to unknown partition returns null
    nullReply := multi.routeRequestVote(999, voteReq)
    verifyNull(nullReply)

    pool.stop
    pool.join
  }
}
