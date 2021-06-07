**
** TxState: Lifecycle progression of a distributed transaction.
**
enum class TxState
{
  active,
  preparing,
  prepared,
  committed,
  aborting,
  aborted
}

**
** IsolationLevel: ANSI SQL / ACID isolation guarantees.
**
enum class IsolationLevel
{
  read_committed,
  repeatable_read,
  serializable
}

**
** TxContext: Transaction state holding read/write buffers, participant cohorts,
** and commit timestamps.
**
class TxContext
{
  const TxId txId
  TxState state := TxState.active
  IsolationLevel isolation
  Int startTimestamp
  Int commitTimestamp := 0

  Str:Obj? readSet := Str:Obj?[:]
  Str:Obj? writeSet := Str:Obj?[:]
  Int[] participantPartitions := Int[,]

  new make(TxId txId, IsolationLevel isolation := IsolationLevel.serializable, Int startTimestamp := DateTime.now.toJava)
  {
    this.txId           = txId
    this.isolation      = isolation
    this.startTimestamp = startTimestamp
  }

  **
  ** Record a read in the transaction readSet.
  **
  Void recordRead(Str key, Obj? val)
  {
    readSet[key] = val
  }

  **
  ** Buffer a write in the transaction writeSet.
  **
  Void bufferWrite(Str key, Obj? val, Int partitionId)
  {
    if (state != TxState.active) throw Err("Cannot write to inactive transaction $txId in state $state")
    writeSet[key] = val
    if (!participantPartitions.contains(partitionId))
    {
      participantPartitions.add(partitionId)
    }
  }

  **
  ** Check if key is buffered in local writeSet.
  **
  Bool hasBufferedWrite(Str key)
  {
    return writeSet.containsKey(key)
  }

  **
  ** Get buffered write value.
  **
  Obj? getBufferedWrite(Str key)
  {
    return writeSet[key]
  }
}
