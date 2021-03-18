**
** Unit tests for LRU and LFU cache eviction policies.
**
class LruLfuPolicyTest : Test
{
  Void testLruEvictionOrder()
  {
    lru := LruPolicy()
    hlc := HybridLogicalClock.now

    e1 := CacheEntry("k1", 1, hlc)
    e2 := CacheEntry("k2", 2, hlc)
    e3 := CacheEntry("k3", 3, hlc)

    lru.recordInsert(e1)
    lru.recordInsert(e2)
    lru.recordInsert(e3)

    verifyEq(lru.size, 3)

    // Touch k1: order becomes k2 (oldest), k3, k1 (newest)
    lru.recordAccess(e1)

    // First eviction must be k2
    verifyEq(lru.evictNext, "k2")
    verifyEq(lru.size, 2)

    // Next eviction must be k3
    verifyEq(lru.evictNext, "k3")

    // Last eviction must be k1
    verifyEq(lru.evictNext, "k1")
    verifyEq(lru.evictNext, null)
  }

  Void testLfuEvictionOrder()
  {
    lfu := LfuPolicy()
    hlc := HybridLogicalClock.now

    eA := CacheEntry("A", 10, hlc)
    eB := CacheEntry("B", 20, hlc)
    eC := CacheEntry("C", 30, hlc)

    lfu.recordInsert(eA)
    lfu.recordInsert(eB)
    lfu.recordInsert(eC)

    // Touch A three times, B once, leave C untouched (freq=1)
    lfu.recordAccess(eA)
    lfu.recordAccess(eA)
    lfu.recordAccess(eB)

    // Frequency: A=3, B=2, C=1
    // First eviction must be C (lowest frequency = 1)
    v1 := lfu.evictNext
    verifyEq(v1, "C")

    // Next eviction must be B (frequency = 2)
    v2 := lfu.evictNext
    verifyEq(v2, "B")

    // Last eviction must be A (frequency = 3)
    v3 := lfu.evictNext
    verifyEq(v3, "A")
    verifyEq(lfu.evictNext, null)
  }
}
