**
** PrepareVote: Participant decision during phase 1 of Two-Phase Commit.
**
enum class PrepareVote
{
  prepared,
  aborted
}

**
** TwoPhaseCommitCoordinator: Orchestrates distributed 2PC across multiple partition cohorts
** guaranteeing atomicity across cross-partition multi-key mutations.
**
** Reference:
** Gray, "Notes on Data Base Operating Systems", IBM Research 1978;
** Bernstein, Hadzilacos, Goodman, "Concurrency Control and Recovery in Database Systems", 1987.
**
class TwoPhaseCommitCoordinator
{
  private NodeId coordinatorNode
  private Int txSeq := 0
  private Str:TxId lockedKeys := Str:TxId[:]

  new make(NodeId coordinatorNode)
  {
    this.coordinatorNode = coordinatorNode
  }

  **
  ** Begin a new distributed transaction context.
  **
  TxContext beginTransaction(IsolationLevel isolation := IsolationLevel.serializable)
  {
    txSeq++
    id := TxId(coordinatorNode, txSeq)
    return TxContext(id, isolation)
  }

  **
  ** Execute atomic Two-Phase Commit protocol across participants.
  ** Returns true if transaction committed successfully, false if aborted.
  **
  Bool commitTransaction(TxContext ctx, Int:PartitionStore storeMap, Str:Int keyToPartitionMap)
  {
    if (ctx.writeSet.isEmpty)
    {
      ctx.state = TxState.committed
      ctx.commitTimestamp = DateTime.now.toJava
      return true
    }

    ctx.state = TxState.preparing

    // ==========================================
    // Phase 1: Prepare
    // ==========================================
    prepareVotes := Int:PrepareVote[:]
    keysAcquired := Str[,]

    ctx.writeSet.each |val, key|
    {
      existingTx := lockedKeys[key]
      if (existingTx != null && existingTx != ctx.txId)
      {
        // Lock contention conflict: reject prepare
        partId := keyToPartitionMap[key] ?: 0
        prepareVotes[partId] = PrepareVote.aborted
      }
      else
      {
        lockedKeys[key] = ctx.txId
        keysAcquired.add(key)
        partId := keyToPartitionMap[key] ?: 0
        if (!prepareVotes.containsKey(partId))
        {
          prepareVotes[partId] = PrepareVote.prepared
        }
      }
    }

    allPrepared := prepareVotes.vals.all |PrepareVote v -> Bool| { v == PrepareVote.prepared }

    // ==========================================
    // Phase 2: Commit or Rollback
    // ==========================================
    if (allPrepared)
    {
      ctx.state = TxState.committed
      ctx.commitTimestamp = DateTime.now.toJava

      // Apply buffered mutations to target partition stores
      ctx.writeSet.each |val, key|
      {
        partId := keyToPartitionMap[key] ?: 0
        store := storeMap[partId]
        if (store != null)
        {
          store.put(key, val)
        }
        lockedKeys.remove(key)
      }
      return true
    }
    else
    {
      ctx.state = TxState.aborted

      // Release acquired prepare locks
      keysAcquired.each |key|
      {
        lockedKeys.remove(key)
      }
      return false
    }
  }

  **
  ** Rollback and abort transaction immediately.
  **
  Void rollbackTransaction(TxContext ctx)
  {
    ctx.state = TxState.aborted
    ctx.writeSet.each |val, key|
    {
      if (lockedKeys[key] == ctx.txId)
      {
        lockedKeys.remove(key)
      }
    }
  }

  **
  ** Check if a key is currently locked by an uncommitted transaction.
  **
  Bool isKeyLocked(Str key)
  {
    return lockedKeys.containsKey(key)
  }
}
