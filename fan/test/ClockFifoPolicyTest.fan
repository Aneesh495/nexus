**
** Unit tests for Clock and FIFO cache eviction policies.
**
class ClockFifoPolicyTest : Test
{
  Void testClockSecondChance()
  {
    clock := ClockPolicy()
    hlc := HybridLogicalClock.now

    e1 := CacheEntry("k1", 1, hlc)
    e2 := CacheEntry("k2", 2, hlc)
    e3 := CacheEntry("k3", 3, hlc)

    clock.recordInsert(e1)
    clock.recordInsert(e2)
    clock.recordInsert(e3)

    // Touch k1 to set its refBit = true
    clock.recordAccess(e1)

    // Clock hand starts at k1 (refBit=true -> cleared to false, advances to k2)
    // k2 (refBit was set upon insert, wait: upon insert refBit is true, let us trace):
    // Hand at k1: bit true -> set to false
    // Hand at k2: bit true -> set to false
    // Hand at k3: bit true -> set to false
    // Touch k2 to re-assert its bit!
    clock.recordAccess(e2)

    // Now k1 has bit=false, k2 has bit=true, k3 has bit=false
    // Hand visits k1 -> victim is k1!
    victim1 := clock.evictNext
    verifyEq(victim1, "k1")

    // Hand is now at index 0 (k2). k2 has bit=false -> victim is k2!
    victim2 := clock.evictNext
    verifyEq(victim2, "k2")

    // Finally k3
    victim3 := clock.evictNext
    verifyEq(victim3, "k3")
    verifyEq(clock.evictNext, null)
  }

  Void testFifoOrder()
  {
    fifo := FifoPolicy()
    hlc := HybridLogicalClock.now

    e1 := CacheEntry("first", 1, hlc)
    e2 := CacheEntry("second", 2, hlc)
    e3 := CacheEntry("third", 3, hlc)

    fifo.recordInsert(e1)
    fifo.recordInsert(e2)
    fifo.recordInsert(e3)

    // Accesses do not change FIFO eviction order
    fifo.recordAccess(e1)

    verifyEq(fifo.evictNext, "first")
    verifyEq(fifo.evictNext, "second")
    verifyEq(fifo.evictNext, "third")
    verifyEq(fifo.evictNext, null)
  }
}
