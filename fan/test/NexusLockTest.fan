**
** Unit tests for NexusLock mutual exclusion, lease timeouts, and monotonic fencing tokens.
**
class NexusLockTest : Test
{
  Void testMutualExclusionAndFencingTokens()
  {
    lock := NexusLock("account:ledger:42")
    verifyEq(lock.lockName, "account:ledger:42")
    verifyFalse(lock.isLocked)

    t0 := 10_000
    // Client 1 acquires lock
    lease1 := lock.tryLock("client-1", 5000, t0)
    verifyNotNull(lease1)
    verifyEq(lease1.ownerId, "client-1")
    verifyEq(lease1.fencingToken, 1)
    verifyTrue(lock.isLocked(t0))
    verifyEq(lock.owner(t0), "client-1")

    // Client 2 attempts acquisition -> rejected
    lease2 := lock.tryLock("client-2", 5000, t0 + 100)
    verifyNull(lease2)

    // Client 1 releases lock
    verifyTrue(lock.unlock("client-1"))
    verifyFalse(lock.isLocked(t0 + 200))

    // Client 2 acquires lock -> receives strictly higher monotonic fencing token (2 > 1)
    lease3 := lock.tryLock("client-2", 5000, t0 + 300)
    verifyNotNull(lease3)
    verifyEq(lease3.ownerId, "client-2")
    verifyEq(lease3.fencingToken, 2)
    verifyTrue(lease3.fencingToken > lease1.fencingToken)
  }

  Void testReentrantAcquisition()
  {
    lock := NexusLock("reentrant-lock")

    // Acquire level 1
    l1 := lock.tryLock("worker-A", 10_000, 1000)
    verifyNotNull(l1)
    verifyEq(lock.getHoldCount, 1)

    // Re-enter level 2
    l2 := lock.tryLock("worker-A", 10_000, 1100)
    verifyNotNull(l2)
    verifyEq(lock.getHoldCount, 2)
    verifyEq(l2.fencingToken, l1.fencingToken) // same token for re-entry

    // Release level 1 -> still locked
    verifyTrue(lock.unlock("worker-A"))
    verifyEq(lock.getHoldCount, 1)
    verifyTrue(lock.isLocked(1200))

    // Release level 2 -> unlocked
    verifyTrue(lock.unlock("worker-A"))
    verifyEq(lock.getHoldCount, 0)
    verifyFalse(lock.isLocked(1300))

    // Unauthorized unlock
    verifyFalse(lock.unlock("worker-B"))
  }

  Void testLeaseTimeoutAutoRelease()
  {
    lock := NexusLock("transient-lock")
    t0 := 10_000

    // Client 1 acquires lock with 2000ms lease
    l1 := lock.tryLock("client-A", 2000, t0)
    verifyNotNull(l1)
    verifyTrue(lock.isLocked(t0 + 1000))

    // Before expiration: Client B cannot acquire
    verifyNull(lock.tryLock("client-B", 2000, t0 + 1500))

    // At t0 + 2500ms (after expiration): Client B acquires with new fencing token
    l2 := lock.tryLock("client-B", 2000, t0 + 2500)
    verifyNotNull(l2)
    verifyEq(l2.ownerId, "client-B")
    verifyEq(l2.fencingToken, 2)
    verifyEq(lock.owner(t0 + 2500), "client-B")
  }

  Void testForceUnlock()
  {
    lock := NexusLock("admin-lock")
    lock.tryLock("rogue-process", 100_000, 1000)
    verifyTrue(lock.isLocked(1000))

    lock.forceUnlock
    verifyFalse(lock.isLocked(1000))
    verifyNull(lock.owner(1000))
  }
}
