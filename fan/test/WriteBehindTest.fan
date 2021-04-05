**
** Unit tests for WriteBehindQueue coalescing and batching.
**
class WriteBehindTest : Test
{
  Void testWriteCoalescing()
  {
    wb := WriteBehindQueue(50, 1000)
    hlc := HybridLogicalClock.now

    // Enqueue 5 rapid updates to same key
    for (i := 1; i <= 5; ++i)
    {
      entry := CacheEntry("counter:hits", i * 100, hlc)
      wb.enqueue(entry)
    }

    // Coalescing: only 1 entry in dirty map
    verifyEq(wb.size, 1)

    batch := wb.drainBatch(10)
    verifyEq(batch.size, 1)
    verifyEq(batch[0].key, "counter:hits")
    verifyEq(batch[0].val, 500) // Latest value preserved
    verify(batch[0].isDirty)

    // Acknowledge flush
    wb.acknowledge(batch)
    verifyEq(batch[0].isDirty, false)
    verifyEq(wb.size, 0)
  }

  Void testFlushTriggers()
  {
    wb := WriteBehindQueue(3, 500)
    hlc := HybridLogicalClock.now
    t0 := 10_000

    verifyEq(wb.shouldFlush(t0), false)

    wb.enqueue(CacheEntry("k1", 1, hlc))
    wb.enqueue(CacheEntry("k2", 2, hlc))
    verifyEq(wb.shouldFlush(t0), false)

    // Batch size reached
    wb.enqueue(CacheEntry("k3", 3, hlc))
    verifyEq(wb.shouldFlush(t0), true)

    batch := wb.drainBatch(10, t0)
    verifyEq(batch.size, 3)
    verifyEq(wb.size, 0)

    // Time trigger
    wb.enqueue(CacheEntry("k4", 4, hlc))
    verifyEq(wb.shouldFlush(t0 + 100), false)
    verifyEq(wb.shouldFlush(t0 + 600), true)
  }

  Void testRetryFailedFlushes()
  {
    wb := WriteBehindQueue(10, 1000)
    hlc := HybridLogicalClock.now

    wb.enqueue(CacheEntry("failMe", "criticalData", hlc))
    batch := wb.drainBatch(10)
    verifyEq(wb.size, 0)

    // Simulate write error: re-enqueue
    wb.retry(batch)
    verifyEq(wb.size, 1)

    retryBatch := wb.drainBatch(10)
    verifyEq(retryBatch.size, 1)
    verifyEq(retryBatch[0].key, "failMe")
  }
}
