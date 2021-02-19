**
** Unit tests for HashUtils (Murmur3, xxHash64, FNV-1a).
**
class HashUtilsTest : Test
{
  Void testMurmur3_32Determinism()
  {
    h1 := HashUtils.murmur3_32Str("nexus-cache-key-alpha", 0)
    h2 := HashUtils.murmur3_32Str("nexus-cache-key-alpha", 0)
    verifyEq(h1, h2)

    // Different seed should yield different hash
    h3 := HashUtils.murmur3_32Str("nexus-cache-key-alpha", 42)
    verify(h1 != h3)

    // Different input should yield different hash
    h4 := HashUtils.murmur3_32Str("nexus-cache-key-beta", 0)
    verify(h1 != h4)
  }

  Void testMurmur3_128And64()
  {
    pair1 := HashUtils.murmur3_128([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], 0)
    verifyEq(pair1.size, 2)
    verify(pair1[0] != 0)
    verify(pair1[1] != 0)

    h64 := HashUtils.murmur3_64Str("consistent-hash-ring-vnode-token")
    verify(h64 != 0)
  }

  Void testXxHash64()
  {
    // Small input (< 32 bytes)
    hSmall1 := HashUtils.xxHash64([1, 2, 3, 4, 5], 0)
    hSmall2 := HashUtils.xxHash64([1, 2, 3, 4, 5], 0)
    verifyEq(hSmall1, hSmall2)

    // Large input (> 32 bytes)
    large := Int[,].fill(42, 64)
    hLarge1 := HashUtils.xxHash64(large, 12345)
    hLarge2 := HashUtils.xxHash64(large, 12345)
    verifyEq(hLarge1, hLarge2)

    largeModified := large.dup
    largeModified[31] = 43
    hLargeMod := HashUtils.xxHash64(largeModified, 12345)
    verify(hLarge1 != hLargeMod)
  }

  Void testFnv1a()
  {
    fnv32a := HashUtils.fnv1a_32Str("test-key-1")
    fnv32b := HashUtils.fnv1a_32Str("test-key-1")
    verifyEq(fnv32a, fnv32b)

    fnv64a := HashUtils.fnv1a_64Str("test-key-1")
    fnv64b := HashUtils.fnv1a_64Str("test-key-1")
    verifyEq(fnv64a, fnv64b)
    verify(fnv64a != 0)
  }

  Void testBitAvalancheMurmur3()
  {
    base := "cache-key-partition-0123"
    flip := "cache-key-partition-0122"

    h1 := HashUtils.murmur3_32Str(base, 0)
    h2 := HashUtils.murmur3_32Str(flip, 0)

    diffBits := 0
    diff := h1.xor(h2)
    for (i := 0; i < 32; ++i)
    {
      if (diff.shiftr(i).and(1) == 1) diffBits++
    }

    // Good avalanche has at least 8 to 24 bits flipped out of 32
    verify(diffBits >= 8)
  }
}
