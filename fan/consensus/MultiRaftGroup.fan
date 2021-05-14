using concurrent

**
** MultiRaftGroupMessage: Container for multiplexed consensus actions across partition groups.
**
const class MultiRaftGroupMessage
{
  const Int partitionId
  const Obj payload

  new make(Int partitionId, Obj payload)
  {
    this.partitionId = partitionId
    this.payload     = payload
  }
}

**
** MultiRaftGroup: Coordinates multiple independent Raft consensus groups
** (one per storage partition) sharing a unified ActorPool and message dispatcher.
**
** Reference:
** CockroachDB Architecture (Multi-Raft Consensus),
** TiKV Multi-Raft Design (Shared Thread Pool and Region State Machines).
**
class MultiRaftGroup
{
  private NodeId localNode
  private ActorPool pool
  private Int:RaftStateMachine groups := Int:RaftStateMachine[:]
  private Int:PartitionStore stores := Int:PartitionStore[:]

  new make(NodeId localNode, ActorPool pool)
  {
    this.localNode = localNode
    this.pool      = pool
  }

  **
  ** Active Raft consensus groups count.
  **
  Int groupCount() { return groups.size }

  **
  ** Registered partition IDs.
  **
  Int[] partitionIds() { return groups.keys }

  **
  ** Lookup state machine for a partition.
  **
  RaftStateMachine? getGroup(Int partitionId)
  {
    return groups[partitionId]
  }

  **
  ** Register a partition consensus group with replica peers and bound PartitionStore.
  **
  RaftStateMachine registerPartition(Int partitionId, NodeId[] peers, PartitionStore store)
  {
    sm := RaftStateMachine(localNode, peers)
    groups[partitionId] = sm
    stores[partitionId] = store
    return sm
  }

  **
  ** Deregister and stop a partition consensus group (e.g. after rebalance migration).
  **
  Void unregisterPartition(Int partitionId)
  {
    groups.remove(partitionId)
    stores.remove(partitionId)
  }

  **
  ** Propose a key-value write operation into the Raft group owning partitionId.
  ** Returns proposed log entry if leader, null otherwise.
  **
  RaftLogEntry? propose(Int partitionId, Str key, Obj? val, Int ttlMillis := 0)
  {
    sm := groups[partitionId]
    if (sm == null || sm.role != RaftRole.leader) return null

    cmd := "PUT\t${key}\t${val}\t${ttlMillis}"
    return sm.propose(cmd)
  }

  **
  ** Execute a batch tick across all hosted partition Raft groups.
  ** Triggers elections on timed-out followers and heartbeats on leaders.
  **
  AppendEntriesArgs[] tickAll(Int nowMillis := DateTime.now.toJava)
  {
    outboundHeartbeats := AppendEntriesArgs[,]
    groups.each |sm, partId|
    {
      if (sm.role == RaftRole.leader)
      {
        hbs := sm.generateHeartbeats
        outboundHeartbeats.addAll(hbs)
      }
      else if (sm.isElectionTimeoutExpired(nowMillis))
      {
        sm.startElection(nowMillis)
      }
    }
    return outboundHeartbeats
  }

  **
  ** Apply newly committed log entries across all groups to their corresponding PartitionStores.
  ** Returns total number of entries applied to local stores.
  **
  Int applyCommitted()
  {
    totalApplied := 0
    groups.each |sm, partId|
    {
      store := stores[partId]
      if (store != null)
      {
        entries := sm.applyCommittedEntries
        entries.each |entry|
        {
          if (entry.type == RaftEntryType.command && entry.payload.startsWith("PUT\t"))
          {
            parts := entry.payload.split('\t')
            if (parts.size >= 4)
            {
              k := parts[1]
              v := parts[2]
              ttl := parts[3].toInt(10, false) ?: 0
              store.put(k, v, ttl)
              totalApplied++
            }
          }
        }
      }
    }
    return totalApplied
  }

  **
  ** Dispatch incoming AppendEntries RPC to target partition state machine.
  **
  AppendEntriesReply? routeAppendEntries(Int partitionId, AppendEntriesArgs args, Int nowMillis := DateTime.now.toJava)
  {
    sm := groups[partitionId]
    if (sm == null) return null
    return sm.handleAppendEntries(args, nowMillis)
  }

  **
  ** Dispatch incoming RequestVote RPC to target partition state machine.
  **
  RequestVoteReply? routeRequestVote(Int partitionId, RequestVoteArgs args, Int nowMillis := DateTime.now.toJava)
  {
    sm := groups[partitionId]
    if (sm == null) return null
    return sm.handleRequestVote(args, nowMillis)
  }
}
