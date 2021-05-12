using concurrent

**
** RaftStateMachine: Deterministic, pure state machine engine executing the Raft consensus algorithm.
**
** Reference:
** Ongaro and Ousterhout, "In Search of an Understandable Consensus Algorithm",
** USENIX ATC 2014.
**
class RaftStateMachine
{
  const NodeId selfId
  const NodeId[] peers

  Int currentTerm := 0
  NodeId? votedFor := null
  RaftRole role := RaftRole.follower
  NodeId? leaderId := null

  RaftLog log
  Int commitIndex := 0
  Int lastApplied := 0

  // Candidate election state
  Str:Bool votesGranted := Str:Bool[:]

  // Leader state: tracked per peer
  Str:Int nextIndexMap := Str:Int[:]
  Str:Int matchIndexMap := Str:Int[:]

  // Linearizable ReadIndex tracking
  private Int:PendingRead pendingReads := Int:PendingRead[:]

  // Election timing
  Int minElectionTimeoutMillis
  Int maxElectionTimeoutMillis
  Int currentElectionTimeoutMillis
  Int lastHeartbeatReceivedMillis := 0
  FastRandom rng

  new make(
    NodeId selfId,
    NodeId[] peers,
    Int minElectionTimeout := 150,
    Int maxElectionTimeout := 300,
    Int seed := 42)
  {
    this.selfId                    = selfId
    this.peers                     = peers.toImmutable
    this.minElectionTimeoutMillis  = minElectionTimeout
    this.maxElectionTimeoutMillis  = maxElectionTimeout
    this.rng                       = FastRandom(seed)
    this.log                       = RaftLog()
    this.currentElectionTimeoutMillis = rng.electionTimeout(minElectionTimeout)
  }

  **
  ** Quorum size required for majority decision: floor((peers.size + 1) / 2) + 1.
  **
  Int quorumSize()
  {
    totalNodes := peers.size + 1
    return (totalNodes / 2) + 1
  }

  **
  ** Check if election timeout has expired since last heartbeat or election start.
  **
  Bool isElectionTimeoutExpired(Int nowMillis)
  {
    return (nowMillis - lastHeartbeatReceivedMillis) >= currentElectionTimeoutMillis
  }

  **
  ** Reset election timer with new randomized timeout.
  **
  Void resetElectionTimeout(Int nowMillis)
  {
    lastHeartbeatReceivedMillis = nowMillis
    currentElectionTimeoutMillis = rng.electionTimeout(minElectionTimeoutMillis)
  }

  **
  ** Step down to follower upon discovering higher term or losing election.
  **
  Void stepDown(Int newTerm, NodeId? newLeader := null)
  {
    this.currentTerm = newTerm
    this.role        = RaftRole.follower
    this.votedFor    = null
    this.leaderId    = newLeader
    this.votesGranted.clear
  }

  **
  ** Initiate leader election after timeout. Transitions to Candidate and requests votes.
  **
  RequestVoteArgs[] startElection(Int nowMillis)
  {
    this.role = RaftRole.candidate
    this.currentTerm++
    this.votedFor = selfId
    this.leaderId = null
    this.votesGranted.clear
    this.votesGranted[selfId.id] = true // vote for self
    resetElectionTimeout(nowMillis)

    // Single-node cluster wins immediately
    if (votesGranted.size >= quorumSize)
    {
      becomeLeader()
      return RequestVoteArgs[,]
    }

    requests := RequestVoteArgs[,]
    peers.each |peer|
    {
      requests.add(RequestVoteArgs(
        currentTerm,
        selfId,
        log.lastIndex,
        log.lastTerm,
        false
      ))
    }
    return requests
  }

  **
  ** Process incoming RequestVote RPC from candidate.
  **
  RequestVoteReply handleRequestVote(RequestVoteArgs args, Int nowMillis := DateTime.now.toJava)
  {
    // Rule 1: If term < currentTerm deny vote
    if (args.term < currentTerm)
    {
      return RequestVoteReply(currentTerm, false, selfId)
    }

    // If term > currentTerm step down
    if (args.term > currentTerm)
    {
      stepDown(args.term)
    }

    // Rule 2: If votedFor is null or candidateId, and candidate log is at least as up-to-date as receiver log
    canVote := (votedFor == null || votedFor == args.candidateId)
    logOk := isCandidateLogUpToDate(args.lastLogIndex, args.lastLogTerm)

    if (canVote && logOk)
    {
      this.votedFor = args.candidateId
      resetElectionTimeout(nowMillis)
      return RequestVoteReply(currentTerm, true, selfId)
    }

    return RequestVoteReply(currentTerm, false, selfId)
  }

  **
  ** Process response to our RequestVote request.
  **
  Bool handleRequestVoteReply(RequestVoteReply reply)
  {
    // If reply has higher term step down immediately
    if (reply.term > currentTerm)
    {
      stepDown(reply.term)
      return false
    }

    if (role != RaftRole.candidate || reply.term != currentTerm)
    {
      return false
    }

    if (reply.voteGranted)
    {
      votesGranted[reply.voterId.id] = true
      if (votesGranted.size >= quorumSize)
      {
        becomeLeader()
        return true
      }
    }
    return false
  }

  **
  ** Transition to leader upon securing quorum votes.
  **
  Void becomeLeader()
  {
    this.role     = RaftRole.leader
    this.leaderId = selfId

    // Initialize leader volatile state
    lastIdx := log.lastIndex
    peers.each |peer|
    {
      nextIndexMap[peer.id]  = lastIdx + 1
      matchIndexMap[peer.id] = 0
    }

    // Append initial empty entry (noop) to establish leadership in new term
    log.append(RaftLogEntry(lastIdx + 1, currentTerm, RaftEntryType.noop, ""))
  }

  **
  ** Generate AppendEntries heartbeat messages to all peers.
  **
  AppendEntriesArgs[] generateHeartbeats()
  {
    if (role != RaftRole.leader) return AppendEntriesArgs[,]

    messages := AppendEntriesArgs[,]
    peers.each |peer|
    {
      prevIdx := (nextIndexMap[peer.id] ?: (log.lastIndex + 1)) - 1
      prevTerm := log.termAt(prevIdx)
      messages.add(AppendEntriesArgs(
        currentTerm,
        selfId,
        prevIdx,
        prevTerm,
        RaftLogEntry[,],
        commitIndex
      ))
    }
    return messages
  }

  **
  ** Client command proposal. Leader appends entry to local log and prepares replication.
  **
  RaftLogEntry? propose(Str payload, RaftEntryType type := RaftEntryType.command)
  {
    if (role != RaftRole.leader) return null

    nextIdx := log.lastIndex + 1
    entry := RaftLogEntry(nextIdx, currentTerm, type, payload)
    log.append(entry)
    return entry
  }

  **
  ** Generate replication AppendEntries RPC for a specific peer.
  **
  AppendEntriesArgs? generateReplication(NodeId peer, Int maxEntries := 50)
  {
    if (role != RaftRole.leader) return null

    peerNext := nextIndexMap[peer.id] ?: (log.lastIndex + 1)
    prevIdx := peerNext - 1
    prevTerm := log.termAt(prevIdx)
    entries := log.entriesFrom(peerNext, maxEntries)

    return AppendEntriesArgs(
      currentTerm,
      selfId,
      prevIdx,
      prevTerm,
      entries,
      commitIndex
    )
  }

  **
  ** Process incoming AppendEntries RPC from leader.
  **
  AppendEntriesReply handleAppendEntries(AppendEntriesArgs args, Int nowMillis := DateTime.now.toJava)
  {
    // Reply false if term < currentTerm
    if (args.term < currentTerm)
    {
      return AppendEntriesReply(currentTerm, false, selfId, log.lastIndex, log.lastIndex)
    }

    // Valid leader heartbeat/append: reset timer and recognize leader
    if (args.term > currentTerm || role != RaftRole.follower)
    {
      stepDown(args.term, args.leaderId)
    }
    else
    {
      this.leaderId = args.leaderId
    }
    resetElectionTimeout(nowMillis)

    // Check log matching property at prevLogIndex
    if (!log.matchTerm(args.prevLogIndex, args.prevLogTerm))
    {
      hint := log.lastIndex.min(args.prevLogIndex - 1).max(0)
      return AppendEntriesReply(currentTerm, false, selfId, 0, hint)
    }

    // Reconcile and append entries
    if (!args.entries.isEmpty)
    {
      log.truncateAndAppend(args.entries.first.index, args.entries)
    }

    // Advance commit index if leaderCommit > commitIndex
    if (args.leaderCommit > commitIndex)
    {
      commitIndex = args.leaderCommit.min(log.lastIndex)
    }

    return AppendEntriesReply(currentTerm, true, selfId, log.lastIndex, 0)
  }

  **
  ** Process AppendEntries reply on leader.
  **
  Bool handleAppendEntriesReply(NodeId peer, AppendEntriesReply reply)
  {
    if (reply.term > currentTerm)
    {
      stepDown(reply.term)
      return false
    }

    if (role != RaftRole.leader || reply.term != currentTerm)
    {
      return false
    }

    if (reply.success)
    {
      matchIndexMap[peer.id] = reply.matchIndex
      nextIndexMap[peer.id]  = reply.matchIndex + 1
      return checkAndAdvanceCommitIndex()
    }
    else
    {
      // Failure due to log divergence: decrement nextIndex
      currNext := nextIndexMap[peer.id] ?: (log.lastIndex + 1)
      if (reply.conflictHintIndex > 0)
      {
        nextIndexMap[peer.id] = reply.conflictHintIndex.max(1)
      }
      else
      {
        nextIndexMap[peer.id] = (currNext - 1).max(1)
      }
      return false
    }
  }

  **
  ** Advance leader commitIndex if an entry in current term is replicated on quorum.
  **
  Bool checkAndAdvanceCommitIndex()
  {
    if (role != RaftRole.leader) return false

    // Collect match indices for all peers + self
    matches := Int[,]
    matches.add(log.lastIndex) // self match index
    peers.each |peer|
    {
      matches.add(matchIndexMap[peer.id] ?: 0)
    }
    matches.sort

    // Median index represents the highest index replicated on majority
    // In sorted list of size N, element at (N - quorumSize) is replicated on >= quorumSize
    quorumIdx := matches[matches.size - quorumSize]

    if (quorumIdx > commitIndex && log.termAt(quorumIdx) == currentTerm)
    {
      commitIndex = quorumIdx
      return true
    }
    return false
  }

  **
  ** Apply committed log entries to local state machine up to commitIndex.
  **
  RaftLogEntry[] applyCommittedEntries()
  {
    if (commitIndex <= lastApplied) return RaftLogEntry[,]

    applied := RaftLogEntry[,]
    for (idx := lastApplied + 1; idx <= commitIndex; ++idx)
    {
      entry := log.entryAt(idx)
      if (entry != null)
      {
        applied.add(entry)
        lastApplied = idx
      }
    }
    return applied
  }

  **
  ** Initiate linearizable ReadIndex query (Section 6.4).
  ** Records current commitIndex and requests quorum confirmation.
  **
  Int startReadIndex(Int reqId)
  {
    if (role != RaftRole.leader) return -1

    read := PendingRead(reqId, commitIndex)
    read.acks[selfId.id] = true
    if (read.acks.size >= quorumSize)
    {
      read.isFulfilled = true
    }
    pendingReads[reqId] = read
    return commitIndex
  }

  **
  ** Record heartbeat acknowledgment from peer for an active ReadIndex request.
  ** Returns true when quorum acknowledgment is achieved.
  **
  Bool recordReadHeartbeatAck(Int reqId, NodeId fromPeer)
  {
    read := pendingReads[reqId]
    if (read == null || read.isFulfilled) return false

    read.acks[fromPeer.id] = true
    if (read.acks.size >= quorumSize)
    {
      read.isFulfilled = true
      return true
    }
    return false
  }

  **
  ** Lookup status of a pending ReadIndex request.
  **
  Int getReadIndex(Int reqId)
  {
    read := pendingReads[reqId]
    if (read == null || !read.isFulfilled) return -1
    return read.readIndex
  }

  **
  ** Section 5.4.1: Candidate log completeness check.
  ** Receiver denies vote if its own log is more up-to-date than candidate log.
  **
  private Bool isCandidateLogUpToDate(Int candidateLastIndex, Int candidateLastTerm)
  {
    myLastTerm  := log.lastTerm
    myLastIndex := log.lastIndex

    if (candidateLastTerm != myLastTerm)
    {
      return candidateLastTerm > myLastTerm
    }
    return candidateLastIndex >= myLastIndex
  }
}

internal class PendingRead
{
  Int reqId
  Int readIndex
  Str:Bool acks := Str:Bool[:]
  Bool isFulfilled := false

  new make(Int reqId, Int readIndex)
  {
    this.reqId     = reqId
    this.readIndex = readIndex
  }
}
