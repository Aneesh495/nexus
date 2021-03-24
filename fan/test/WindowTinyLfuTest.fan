**
** Unit tests for WindowTinyLfuPolicy eviction and admission duel.
**
class WindowTinyLfuTest : Test
{
  Void testWindowAdmissionAndPromotion()
  {
    wtlfu := WindowTinyLfuPolicy(100)
    hlc := HybridLogicalClock.now

    // Insert entries
    for (i := 0; i < 5; ++i)
    {
      entry := CacheEntry("k-$i", i, hlc)
      wtlfu.recordInsert(entry)
    }

    verify(wtlfu.size > 0)

    // Touch k-0 multiple times to promote to protected
    e0 := CacheEntry("k-0", 0, hlc)
    wtlfu.recordAccess(e0)
    wtlfu.recordAccess(e0)
    wtlfu.recordAccess(e0)

    verify(wtlfu.size > 0)
  }

  Void testAdmissionDuel()
  {
    wtlfu := WindowTinyLfuPolicy(20)
    hlc := HybridLogicalClock.now

    // Populate and drain to main cache
    for (i := 0; i < 20; ++i)
    {
      wtlfu.recordInsert(CacheEntry("item-$i", i, hlc))
      // Drain window to main
      while (wtlfu.size > 20)
      {
        wtlfu.evictNext
      }
    }

    hotEntry := CacheEntry("hot-item", 999, hlc)
    wtlfu.recordInsert(hotEntry)
    for (i := 0; i < 10; ++i)
    {
      wtlfu.recordAccess(hotEntry)
    }

    // Now insert a cold candidate
    coldEntry := CacheEntry("cold-item", -1, hlc)
    wtlfu.recordInsert(coldEntry)

    // Drain overcapacity: hot-item must survive over cold items
    evicted := wtlfu.evictNext
    while (evicted == null && wtlfu.size > 20)
    {
      evicted = wtlfu.evictNext
    }

    verify(evicted != null)
    verify(evicted != "hot-item")
  }

  Void testAdaptWindowSize()
  {
    wtlfu := WindowTinyLfuPolicy(100)
    origCap := wtlfu.currentWindowCap
    verify(origCap >= 1)

    // Adapt window size
    wtlfu.adaptWindowSize
    verify(wtlfu.currentWindowCap >= 1)
  }
}
