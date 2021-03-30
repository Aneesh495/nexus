**
** Unit tests for PartitionStore storage kernel.
**
class PartitionStoreTest : Test
{
  Void testPutGetAndTelemetry()
  {
    store := PartitionStore(0, 100)
    verifyEq(store.size, 0)

    store.put("key1", "val1")
    store.put("key2", "val2")

    verifyEq(store.size, 2)
    verifyEq(store.get("key1").val, "val1")
    verifyEq(store.get("key2").val, "val2")
    verifyEq(store.get("unknown"), null)

    verifyEq(store.hitCount, 2)
    verifyEq(store.missCount, 1)

    // Put if absent
    res1 := store.putIfAbsent("key1", "newVal")
    verifyEq(res1, null)
    verifyEq(store.get("key1").val, "val1")

    res2 := store.putIfAbsent("key3", "val3")
    verify(res2 != null)
    verifyEq(store.get("key3").val, "val3")
  }

  Void testTtlExpiration()
  {
    t0 := DateTime.now.toJava
    store := PartitionStore(1, 100)

    // Put with 100ms TTL
    store.put("tempKey", "willExpire", 100, null, t0)
    verifyEq(store.get("tempKey", t0).val, "willExpire")

    // Expired query
    verifyEq(store.get("tempKey", t0 + 150), null)

    // Batch eviction sweep
    store.put("temp2", "expireSoon", 50, null, t0)
    evicted := store.evictExpired(t0 + 60)
    verify(evicted >= 1)
  }

  Void testCapacityEviction()
  {
    maxCap := 16
    store := PartitionStore(2, maxCap, 1024 * 1024, LruPolicy())

    for (i := 0; i < 25; ++i)
    {
      store.put("key-$i", i)
    }

    // Must not exceed max capacity
    verify(store.size <= maxCap)
    verify(store.evictionCount > 0)
  }

  Void testRangeAndPrefixScan()
  {
    store := PartitionStore(3, 100)
    store.put("order:2026:01", 100)
    store.put("order:2026:02", 200)
    store.put("order:2026:03", 300)
    store.put("user:profile", "Alice")

    scanOrders := store.prefixScan("order:2026:")
    verifyEq(scanOrders.size, 3)
    verifyEq(scanOrders["order:2026:01"].val, 100)
    verifyEq(scanOrders["order:2026:03"].val, 300)

    range := store.range("order:2026:01", "order:2026:03")
    verifyEq(range.size, 2)
  }
}
