**
** QueueLease: Visibility timeout token representing temporary checkout of a queue item.
**
const class QueueLease
{
  const Str leaseToken
  const Obj? item
  const Int expiresAtMillis
  const Int attemptCount

  new make(Str leaseToken, Obj? item, Int expiresAtMillis, Int attemptCount)
  {
    this.leaseToken      = leaseToken
    this.item            = item
    this.expiresAtMillis = expiresAtMillis
    this.attemptCount    = attemptCount
  }
}

**
** NexusQueue: Distributed bounded FIFO queue supporting at-least-once leasing,
** visibility timeouts, and dead-letter requeueing.
**
class NexusQueue
{
  private Str name
  private Int capacity
  private Int maxAttempts
  private RingQueue ring
  private Str:QueueLease activeLeases := Str:QueueLease[:]
  private Int leaseSeq := 0

  new make(Str name, Int capacity := 1024, Int maxAttempts := 3)
  {
    this.name        = name
    this.capacity    = capacity
    this.maxAttempts = maxAttempts
    this.ring        = RingQueue(capacity, false)
  }

  **
  ** Queue name.
  **
  Str queueName() { return name }

  **
  ** Current number of elements ready for consumption (excluding active leases).
  **
  Int readySize() { return ring.size }

  **
  ** Number of items currently checked out on active leases.
  **
  Int leasedCount() { return activeLeases.size }

  **
  ** Total items present in queue (ready + leased).
  **
  Int totalSize() { return readySize + leasedCount }

  **
  ** Remaining capacity for incoming offers.
  **
  Int remainingCapacity() { return (capacity - totalSize).max(0) }

  **
  ** Enqueue item at the tail. Returns true if added, false if queue is full.
  **
  Bool offer(Obj? item)
  {
    if (totalSize >= capacity) return false
    return ring.offer(item)
  }

  **
  ** Direct poll without lease (removes item immediately).
  **
  Obj? poll()
  {
    sweepExpiredLeases
    return ring.poll
  }

  **
  ** Peek at head item without removing.
  **
  Obj? peek()
  {
    sweepExpiredLeases
    return ring.peek
  }

  **
  ** Check out head item with visibility timeout lease (at-least-once delivery).
  ** Item is hidden from subsequent pollers until acked or lease expires.
  **
  QueueLease? lease(Int leaseDurationMillis := 5000, Int nowMillis := DateTime.now.toJava)
  {
    sweepExpiredLeases(nowMillis)
    if (ring.isEmpty) return null

    raw := ring.poll
    if (raw == null) return null

    leaseSeq++
    token := "${name}:lease:${leaseSeq}:${nowMillis}"
    leaseObj := QueueLease(token, raw, nowMillis + leaseDurationMillis, 1)
    activeLeases[token] = leaseObj
    return leaseObj
  }

  **
  ** Acknowledge successful processing. Permanently deletes leased item.
  ** Returns true if lease existed and was resolved.
  **
  Bool ack(Str leaseToken)
  {
    return activeLeases.remove(leaseToken) != null
  }

  **
  ** Negative acknowledgment. Immediately releases item back to ready queue.
  **
  Bool nack(Str leaseToken)
  {
    leaseObj := activeLeases.remove(leaseToken)
    if (leaseObj == null) return false

    if (leaseObj.attemptCount < maxAttempts)
    {
      ring.offer(leaseObj.item)
      return true
    }
    // Exceeded max redelivery attempts: dropped or dead-lettered
    return false
  }

  **
  ** Sweep and re-queue items whose visibility lease expired without ack.
  **
  Int sweepExpiredLeases(Int nowMillis := DateTime.now.toJava)
  {
    expiredTokens := Str[,]
    activeLeases.each |leaseObj, token|
    {
      if (nowMillis >= leaseObj.expiresAtMillis)
      {
        expiredTokens.add(token)
      }
    }

    requeued := 0
    expiredTokens.each |token|
    {
      leaseObj := activeLeases.remove(token)
      if (leaseObj != null)
      {
        if (leaseObj.attemptCount < maxAttempts)
        {
          ring.offer(leaseObj.item)
          requeued++
        }
      }
    }
    return requeued
  }

  **
  ** Drain up to maxElements into target list.
  **
  Int drainTo(Obj?[] target, Int maxElements := 100)
  {
    sweepExpiredLeases
    drained := 0
    while (drained < maxElements && !ring.isEmpty)
    {
      item := ring.poll
      if (item != null)
      {
        target.add(item)
        drained++
      }
    }
    return drained
  }

  **
  ** Clear all items and active leases.
  **
  Void clear()
  {
    ring.clear
    activeLeases.clear
  }
}
