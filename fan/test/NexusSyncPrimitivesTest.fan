**
** Unit tests for NexusSemaphore and NexusCountDownLatch synchronization primitives.
**
class NexusSyncPrimitivesTest : Test
{
  Void testSemaphorePermitsAndDrain()
  {
    sem := NexusSemaphore("conn-pool", 3, 10)
    verifyEq(sem.semaphoreName, "conn-pool")
    verifyEq(sem.availablePermits, 3)

    // Acquire 2 permits
    verifyTrue(sem.tryAcquire(2))
    verifyEq(sem.availablePermits, 1)

    // Attempt to acquire 2 permits -> fails (only 1 left)
    verifyFalse(sem.tryAcquire(2))
    verifyEq(sem.availablePermits, 1)

    // Acquire remaining 1 permit
    verifyTrue(sem.tryAcquire(1))
    verifyEq(sem.availablePermits, 0)
    verifyFalse(sem.tryAcquire(1))

    // Release 2 permits
    sem.release(2)
    verifyEq(sem.availablePermits, 2)

    // Drain permits
    drained := sem.drainPermits
    verifyEq(drained, 2)
    verifyEq(sem.availablePermits, 0)

    // Reduce permits
    sem.release(5)
    sem.reducePermits(2)
    verifyEq(sem.availablePermits, 3)
  }

  Void testCountDownLatchCountdownAndAwait()
  {
    latch := NexusCountDownLatch("cluster-startup", 3)
    verifyEq(latch.latchName, "cluster-startup")
    verifyEq(latch.getCount, 3)
    verifyFalse(latch.await)

    // Count down 1
    reachedZero1 := latch.countDown
    verifyFalse(reachedZero1)
    verifyEq(latch.getCount, 2)
    verifyFalse(latch.await)

    // Count down 2
    reachedZero2 := latch.countDown
    verifyFalse(reachedZero2)
    verifyEq(latch.getCount, 1)

    // Count down 3 -> hits zero
    reachedZero3 := latch.countDown
    verifyTrue(reachedZero3)
    verifyEq(latch.getCount, 0)
    verifyTrue(latch.await)

    // Further countdowns stay at zero
    verifyFalse(latch.countDown)
    verifyEq(latch.getCount, 0)
    verifyTrue(latch.await)

    // Reset latch
    latch.reset(2)
    verifyEq(latch.getCount, 2)
    verifyFalse(latch.await)
  }
}
