**
** NexusSemaphore: Distributed counting semaphore coordinating shared resource concurrency.
**
** Reference:
** Java java.util.concurrent.Semaphore,
** Hazelcast ISemaphore distributed synchronization primitive.
**
class NexusSemaphore
{
  private Str name
  private Int permits
  private Int maxPermits

  new make(Str name, Int initialPermits := 1, Int maxPermits := 100_000)
  {
    this.name       = name
    this.permits    = initialPermits.max(0)
    this.maxPermits = maxPermits
  }

  **
  ** Semaphore resource name.
  **
  Str semaphoreName() { return name }

  **
  ** Number of currently available permits.
  **
  Int availablePermits() { return permits }

  **
  ** Try acquiring permits. Returns true if granted, false if insufficient permits.
  **
  Bool tryAcquire(Int count := 1)
  {
    if (count <= 0) return true
    if (permits >= count)
    {
      permits -= count
      return true
    }
    return false
  }

  **
  ** Release permits back to the semaphore pool.
  **
  Void release(Int count := 1)
  {
    if (count <= 0) return
    permits = (permits + count).min(maxPermits)
  }

  **
  ** Drain and acquire all currently available permits. Returns drained count.
  **
  Int drainPermits()
  {
    drained := permits
    permits = 0
    return drained
  }

  **
  ** Reduce available permits by reduction amount without blocking.
  **
  Void reducePermits(Int reduction)
  {
    if (reduction <= 0) return
    permits = (permits - reduction).max(0)
  }
}

**
** NexusCountDownLatch: Distributed rendezvous barrier synchronization primitive.
**
** Reference:
** Java java.util.concurrent.CountDownLatch,
** Hazelcast ICountDownLatch distributed barrier.
**
class NexusCountDownLatch
{
  private Str name
  private Int count

  new make(Str name, Int initialCount := 1)
  {
    this.name  = name
    this.count = initialCount.max(0)
  }

  **
  ** Latch resource name.
  **
  Str latchName() { return name }

  **
  ** Current remaining barrier count.
  **
  Int getCount() { return count }

  **
  ** Decrement latch count. Returns true if count reached zero with this decrement.
  **
  Bool countDown()
  {
    if (count > 0)
    {
      count--
      return count == 0
    }
    return false
  }

  **
  ** Check if the latch has reached zero.
  **
  Bool await()
  {
    return count == 0
  }

  **
  ** Reset the latch to a new count.
  **
  Void reset(Int newCount)
  {
    this.count = newCount.max(0)
  }
}
