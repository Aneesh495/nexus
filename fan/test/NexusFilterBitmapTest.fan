**
** Unit tests for NexusBloomFilter and NexusBitmap probabilistic and indexing structures.
**
class NexusFilterBitmapTest : Test
{
  Void testBloomFilterZeroFalseNegatives()
  {
    bf := NexusBloomFilter(1000, 0.01f)
    verifyEq(bf.size, 0)

    // Add 500 items
    500.times |i|
    {
      bf.add("user-${i}@example.com")
    }
    verifyEq(bf.size, 500)

    // Every added item MUST be present (zero false negatives)
    500.times |i|
    {
      verifyTrue(bf.mightContain("user-${i}@example.com"))
    }

    // Check false positive rate on unadded items
    falsePositives := 0
    1000.times |i|
    {
      if (bf.mightContain("unknown-user-${i}@other.org"))
      {
        falsePositives++
      }
    }

    // False positives should be small (< 30 out of 1000, i.e. < 3%)
    verifyTrue(falsePositives < 30)

    // Expected FPP
    verifyTrue(bf.expectedFpp < 0.05f)

    bf.clear
    verifyEq(bf.size, 0)
    verifyFalse(bf.mightContain("user-0@example.com"))
  }

  Void testBitmapSetGetAndCardinality()
  {
    bm := NexusBitmap()
    verifyTrue(bm.isEmpty)
    verifyEq(bm.cardinality, 0)

    // Set bits in first word
    bm.set(0)
    bm.set(10)
    bm.set(63)
    verifyEq(bm.cardinality, 3)
    verifyFalse(bm.isEmpty)

    verifyTrue(bm.get(0))
    verifyTrue(bm.get(10))
    verifyTrue(bm.get(63))
    verifyFalse(bm.get(1))
    verifyFalse(bm.get(62))

    // Set bit in higher word (dynamic expansion)
    bm.set(500)
    verifyTrue(bm.get(500))
    verifyEq(bm.cardinality, 4)
    verifyTrue(bm.wordCount >= 8)

    // Clear bit
    bm.clearBit(10)
    verifyFalse(bm.get(10))
    verifyEq(bm.cardinality, 3)
  }

  Void testBitmapBitwiseOperations()
  {
    bm1 := NexusBitmap()
    bm1.set(1)
    bm1.set(2)
    bm1.set(3)

    bm2 := NexusBitmap()
    bm2.set(2)
    bm2.set(3)
    bm2.set(4)

    // OR (union): 1, 2, 3, 4
    orBm := NexusBitmap()
    orBm.or(bm1)
    orBm.or(bm2)
    verifyEq(orBm.cardinality, 4)
    verifyTrue(orBm.get(1) && orBm.get(4))

    // AND (intersection): 2, 3
    andBm := NexusBitmap()
    andBm.or(bm1)
    andBm.and(bm2)
    verifyEq(andBm.cardinality, 2)
    verifyTrue(andBm.get(2) && andBm.get(3))
    verifyFalse(andBm.get(1))

    // XOR (symmetric difference): 1, 4
    xorBm := NexusBitmap()
    xorBm.or(bm1)
    xorBm.xor(bm2)
    verifyEq(xorBm.cardinality, 2)
    verifyTrue(xorBm.get(1) && xorBm.get(4))
    verifyFalse(xorBm.get(2))

    // AND NOT (difference): 1
    diffBm := NexusBitmap()
    diffBm.or(bm1)
    diffBm.andNot(bm2)
    verifyEq(diffBm.cardinality, 1)
    verifyTrue(diffBm.get(1))
    verifyFalse(diffBm.get(2))
  }
}
