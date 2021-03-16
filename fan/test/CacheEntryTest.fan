**
** Unit tests for CacheEntry cell and telemetry.
**
class CacheEntryTest : Test
{
  Void testInitializationAndExpiry()
  {
    t0 := 1000
    hlc := HybridLogicalClock(t0, 0)
    entry := CacheEntry("user:42", "payload", hlc, 500, t0)

    verifyEq(entry.key, "user:42")
    verifyEq(entry.val, "payload")
    verifyEq(entry.createTime, t0)
    verifyEq(entry.expireTime, 1500)
    verifyEq(entry.isExpired(1400), false)
    verifyEq(entry.isExpired(1500), true)
    verifyEq(entry.isExpired(1600), true)
  }

  Void testImmortalEntry()
  {
    hlc := HybridLogicalClock(1000, 0)
    entry := CacheEntry("session:forever", 123, hlc, 0, 1000)

    verifyEq(entry.expireTime, 0)
    verifyEq(entry.isExpired(999999999), false)
  }

  Void testFlags()
  {
    hlc := HybridLogicalClock.now
    entry := CacheEntry("key", "val", hlc)

    verifyEq(entry.isTombstone, false)
    verifyEq(entry.isDirty, false)
    verifyEq(entry.isLocked, false)

    entry.setTombstone(true)
    verifyEq(entry.isTombstone, true)

    entry.setDirty(true)
    verifyEq(entry.isDirty, true)

    entry.setLocked(true)
    verifyEq(entry.isLocked, true)

    entry.setTombstone(false)
    verifyEq(entry.isTombstone, false)
    verifyEq(entry.isDirty, true)
    verifyEq(entry.isLocked, true)
  }

  Void testTouchAndCost()
  {
    hlc := HybridLogicalClock.now
    entry := CacheEntry("test-key", "test-val", hlc)

    verifyEq(entry.accessCount, 1)
    entry.touch(2000)
    verifyEq(entry.accessCount, 2)
    verifyEq(entry.lastAccessTime, 2000)

    verify(entry.costBytes > 50)
  }
}
