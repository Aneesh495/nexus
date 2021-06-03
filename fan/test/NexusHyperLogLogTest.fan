**
** Unit tests for NexusHyperLogLog cardinality estimation and merge operators.
**
class NexusHyperLogLogTest : Test
{
  Void testEmptyHll()
  {
    hll := NexusHyperLogLog(10)
    verifyEq(hll.bucketCount, 1024)
    verifyEq(hll.precision, 10)
    verifyEq(hll.estimate, 0)
  }

  Void testSmallCardinalityLinearCounting()
  {
    hll := NexusHyperLogLog(12)
    // Add 100 distinct items
    100.times |i|
    {
      hll.add("item-${i}")
    }

    est := hll.estimate
    // Within 5% error for small sets
    verifyTrue(est >= 92 && est <= 108)
  }

  Void testMediumCardinalityAndIdempotence()
  {
    hll := NexusHyperLogLog(12) // 4096 registers, ~1.6% std error
    numItems := 5000

    // Add 5,000 distinct items
    numItems.times |i|
    {
      hll.add("metric-uuid-${i}")
    }

    est := hll.estimate
    // Theoretical 3-sigma error: < 5% error (between 4,750 and 5,250)
    verifyTrue(est >= 4750 && est <= 5250)

    // Re-adding same items must not inflate estimate (idempotence)
    1000.times |i|
    {
      hll.add("metric-uuid-${i}")
    }
    estAfterDups := hll.estimate
    verifyEq(estAfterDups, est)
  }

  Void testDistributedMerge()
  {
    hllA := NexusHyperLogLog(12)
    hllB := NexusHyperLogLog(12)

    // Partition A receives items 0..2499
    2500.times |i|
    {
      hllA.add("partition-key-${i}")
    }

    // Partition B receives items 2500..4999
    2500.times |i|
    {
      hllB.add("partition-key-${2500 + i}")
    }

    // Merge B into A
    hllA.merge(hllB)
    mergedEstimate := hllA.estimate

    // Merged estimate covers all 5000 items
    verifyTrue(mergedEstimate >= 4750 && mergedEstimate <= 5250)
  }

  Void testIncompatibleMergeRejection()
  {
    hll1 := NexusHyperLogLog(10)
    hll2 := NexusHyperLogLog(12)
    verifyErr(ArgErr#) { hll1.merge(hll2) }
  }
}
