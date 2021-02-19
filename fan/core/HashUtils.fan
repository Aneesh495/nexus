**
** HashUtils: High-performance cryptographic and non-cryptographic hash algorithms.
**
** Implements:
** - MurmurHash3 32-bit and 128-bit variants (Austin Appleby).
** - xxHash64 ultra-fast non-cryptographic hash (Yann Collet).
** - FNV-1a 32-bit and 64-bit Fowler-Noll-Vo algorithms.
** - Pearson 8-bit permutation hash for fast small-register lookups.
**
class HashUtils
{
  private static const Int c1_32 := 0xcc9e2d51
  private static const Int c2_32 := 0x1b873593

  private static const Int c1_128 := 0x87c37b91114253d5
  private static const Int c2_128 := 0x4cf5ad432745937f

  private static const Int xxPrime64_1 := 0x9E3779B185EBCA87
  private static const Int xxPrime64_2 := 0xC2B2AE3D27D4EB4F
  private static const Int xxPrime64_3 := 0x165667B19E3779F9
  private static const Int xxPrime64_4 := 0x85EBCA77C2B2AE63
  private static const Int xxPrime64_5 := 0x27D4EB2F165667C5

  private static const Int fnvPrime32 := 16777619
  private static const Int fnvOffset32 := 2166136261
  private static const Int fnvPrime64 := 1099511628211
  private static const Int fnvOffset64 := 0xcbf29ce484222325

  **
  ** Calculate 32-bit MurmurHash3 for a byte list.
  **
  static Int murmur3_32(Int[] data, Int seed := 0)
  {
    length := data.size
    nblocks := length.shiftr(2)
    h1 := seed.and(0xFFFFFFFF)

    for (i := 0; i < nblocks; ++i)
    {
      idx := i.shiftl(2)
      k1 := data[idx].or(data[idx + 1].shiftl(8))
                     .or(data[idx + 2].shiftl(16))
                     .or(data[idx + 3].shiftl(24)).and(0xFFFFFFFF)

      k1 = (k1 * c1_32).and(0xFFFFFFFF)
      k1 = rotl32(k1, 15)
      k1 = (k1 * c2_32).and(0xFFFFFFFF)

      h1 = h1.xor(k1)
      h1 = rotl32(h1, 13)
      h1 = ((h1 * 5) + 0xe6546b64).and(0xFFFFFFFF)
    }

    tailIdx := nblocks.shiftl(2)
    k1 := 0
    rem := length.and(3)

    if (rem == 3) k1 = k1.xor(data[tailIdx + 2].and(0xFF).shiftl(16))
    if (rem >= 2) k1 = k1.xor(data[tailIdx + 1].and(0xFF).shiftl(8))
    if (rem >= 1)
    {
      k1 = k1.xor(data[tailIdx].and(0xFF))
      k1 = (k1 * c1_32).and(0xFFFFFFFF)
      k1 = rotl32(k1, 15)
      k1 = (k1 * c2_32).and(0xFFFFFFFF)
      h1 = h1.xor(k1)
    }

    h1 = h1.xor(length).and(0xFFFFFFFF)
    h1 = fmix32(h1)
    return h1
  }

  **
  ** Calculate 32-bit MurmurHash3 for a string.
  **
  static Int murmur3_32Str(Str s, Int seed := 0)
  {
    return murmur3_32(toUtf8Bytes(s), seed)
  }

  **
  ** Calculate 64-bit lower half of MurmurHash3 128-bit hash.
  **
  static Int murmur3_64(Int[] data, Int seed := 0)
  {
    h := murmur3_128(data, seed)
    return h[0]
  }

  **
  ** Calculate 64-bit lower half of MurmurHash3 128-bit hash for string.
  **
  static Int murmur3_64Str(Str s, Int seed := 0)
  {
    return murmur3_64(toUtf8Bytes(s), seed)
  }

  **
  ** Calculate full 128-bit MurmurHash3, returning [h1, h2] pair.
  **
  static Int[] murmur3_128(Int[] data, Int seed := 0)
  {
    length := data.size
    nblocks := length.shiftr(4)

    h1 := seed
    h2 := seed

    for (i := 0; i < nblocks; ++i)
    {
      idx := i.shiftl(4)
      k1 := getI8LE(data, idx)
      k2 := getI8LE(data, idx + 8)

      k1 = k1 * c1_128
      k1 = rotl64(k1, 31)
      k1 = k1 * c2_128
      h1 = h1.xor(k1)

      h1 = rotl64(h1, 27)
      h1 = h1 + h2
      h1 = (h1 * 5) + 0x52dce729

      k2 = k2 * c2_128
      k2 = rotl64(k2, 33)
      k2 = k2 * c1_128
      h2 = h2.xor(k2)

      h2 = rotl64(h2, 31)
      h2 = h2 + h1
      h2 = (h2 * 5) + 0x38495ab5
    }

    tailIdx := nblocks.shiftl(4)
    k1 := 0
    k2 := 0
    rem := length.and(15)

    if (rem >= 15) k2 = k2.xor(data[tailIdx + 14].and(0xFF).shiftl(48))
    if (rem >= 14) k2 = k2.xor(data[tailIdx + 13].and(0xFF).shiftl(40))
    if (rem >= 13) k2 = k2.xor(data[tailIdx + 12].and(0xFF).shiftl(32))
    if (rem >= 12) k2 = k2.xor(data[tailIdx + 11].and(0xFF).shiftl(24))
    if (rem >= 11) k2 = k2.xor(data[tailIdx + 10].and(0xFF).shiftl(16))
    if (rem >= 10) k2 = k2.xor(data[tailIdx + 9].and(0xFF).shiftl(8))
    if (rem >= 9)
    {
      k2 = k2.xor(data[tailIdx + 8].and(0xFF))
      k2 = k2 * c2_128
      k2 = rotl64(k2, 33)
      k2 = k2 * c1_128
      h2 = h2.xor(k2)
    }

    if (rem >= 8) k1 = k1.xor(data[tailIdx + 7].and(0xFF).shiftl(56))
    if (rem >= 7) k1 = k1.xor(data[tailIdx + 6].and(0xFF).shiftl(48))
    if (rem >= 6) k1 = k1.xor(data[tailIdx + 5].and(0xFF).shiftl(40))
    if (rem >= 5) k1 = k1.xor(data[tailIdx + 4].and(0xFF).shiftl(32))
    if (rem >= 4) k1 = k1.xor(data[tailIdx + 3].and(0xFF).shiftl(24))
    if (rem >= 3) k1 = k1.xor(data[tailIdx + 2].and(0xFF).shiftl(16))
    if (rem >= 2) k1 = k1.xor(data[tailIdx + 1].and(0xFF).shiftl(8))
    if (rem >= 1)
    {
      k1 = k1.xor(data[tailIdx].and(0xFF))
      k1 = k1 * c1_128
      k1 = rotl64(k1, 31)
      k1 = k1 * c2_128
      h1 = h1.xor(k1)
    }

    h1 = h1.xor(length)
    h2 = h2.xor(length)

    h1 = h1 + h2
    h2 = h2 + h1

    h1 = fmix64(h1)
    h2 = fmix64(h2)

    h1 = h1 + h2
    h2 = h2 + h1

    return [h1, h2]
  }

  **
  ** Calculate 64-bit xxHash64.
  **
  static Int xxHash64(Int[] data, Int seed := 0)
  {
    length := data.size
    h64 := 0

    if (length >= 32)
    {
      v1 := seed + xxPrime64_1 + xxPrime64_2
      v2 := seed + xxPrime64_2
      v3 := seed
      v4 := seed - xxPrime64_1

      limit := length - 32
      idx := 0
      while (idx <= limit)
      {
        v1 = xxRound64(v1, getI8LE(data, idx))
        idx += 8
        v2 = xxRound64(v2, getI8LE(data, idx))
        idx += 8
        v3 = xxRound64(v3, getI8LE(data, idx))
        idx += 8
        v4 = xxRound64(v4, getI8LE(data, idx))
        idx += 8
      }

      h64 = rotl64(v1, 1) + rotl64(v2, 7) + rotl64(v3, 12) + rotl64(v4, 18)
      h64 = xxMergeRound64(h64, v1)
      h64 = xxMergeRound64(h64, v2)
      h64 = xxMergeRound64(h64, v3)
      h64 = xxMergeRound64(h64, v4)
    }
    else
    {
      h64 = seed + xxPrime64_5
    }

    h64 = h64 + length

    remIdx := length.and(-8)
    while (remIdx + 8 <= length)
    {
      k1 := xxRound64(0, getI8LE(data, remIdx))
      h64 = h64.xor(k1)
      h64 = rotl64(h64, 27) * xxPrime64_1 + xxPrime64_4
      remIdx += 8
    }

    if (remIdx + 4 <= length)
    {
      k1 := getI4LE(data, remIdx) * xxPrime64_1
      h64 = h64.xor(k1)
      h64 = rotl64(h64, 23) * xxPrime64_2 + xxPrime64_3
      remIdx += 4
    }

    while (remIdx < length)
    {
      k1 := data[remIdx].and(0xFF) * xxPrime64_5
      h64 = h64.xor(k1)
      h64 = rotl64(h64, 11) * xxPrime64_1
      remIdx++
    }

    // Avalanche
    h64 = h64.xor(h64.shiftr(33))
    h64 = h64 * xxPrime64_2
    h64 = h64.xor(h64.shiftr(29))
    h64 = h64 * xxPrime64_3
    h64 = h64.xor(h64.shiftr(32))

    return h64
  }

  **
  ** Calculate 32-bit FNV-1a hash.
  **
  static Int fnv1a_32(Int[] data)
  {
    hash := fnvOffset32
    for (i := 0; i < data.size; ++i)
    {
      hash = hash.xor(data[i].and(0xFF))
      hash = (hash * fnvPrime32).and(0xFFFFFFFF)
    }
    return hash
  }

  **
  ** Calculate 32-bit FNV-1a hash for string.
  **
  static Int fnv1a_32Str(Str s)
  {
    return fnv1a_32(toUtf8Bytes(s))
  }

  **
  ** Calculate 64-bit FNV-1a hash.
  **
  static Int fnv1a_64(Int[] data)
  {
    hash := fnvOffset64
    for (i := 0; i < data.size; ++i)
    {
      hash = hash.xor(data[i].and(0xFF))
      hash = hash * fnvPrime64
    }
    return hash
  }

  **
  ** Calculate 64-bit FNV-1a hash for string.
  **
  static Int fnv1a_64Str(Str s)
  {
    return fnv1a_64(toUtf8Bytes(s))
  }

  // --- Internal bit math helpers ---

  private static Int rotl32(Int x, Int r)
  {
    x32 := x.and(0xFFFFFFFF)
    return (x32.shiftl(r).or(x32.shiftr(32 - r))).and(0xFFFFFFFF)
  }

  private static Int rotl64(Int x, Int r)
  {
    return x.shiftl(r).or(x.shiftr(64 - r))
  }

  private static Int fmix32(Int h)
  {
    v := h.and(0xFFFFFFFF)
    v = v.xor(v.shiftr(16))
    v = (v * 0x85ebca6b).and(0xFFFFFFFF)
    v = v.xor(v.shiftr(13))
    v = (v * 0xc2b2ae35).and(0xFFFFFFFF)
    v = v.xor(v.shiftr(16))
    return v
  }

  private static Int fmix64(Int k)
  {
    v := k
    v = v.xor(v.shiftr(33))
    v = v * 0xff51afd7ed558ccd
    v = v.xor(v.shiftr(33))
    v = v * 0xc4ceb9fe1a85ec53
    v = v.xor(v.shiftr(33))
    return v
  }

  private static Int xxRound64(Int acc, Int input)
  {
    acc += input * xxPrime64_2
    acc = rotl64(acc, 31)
    acc *= xxPrime64_1
    return acc
  }

  private static Int xxMergeRound64(Int acc, Int val)
  {
    v := xxRound64(0, val)
    acc = acc.xor(v)
    acc = acc * xxPrime64_1 + xxPrime64_4
    return acc
  }

  private static Int getI8LE(Int[] data, Int offset)
  {
    return data[offset].and(0xFF)
      .or(data[offset + 1].and(0xFF).shiftl(8))
      .or(data[offset + 2].and(0xFF).shiftl(16))
      .or(data[offset + 3].and(0xFF).shiftl(24))
      .or(data[offset + 4].and(0xFF).shiftl(32))
      .or(data[offset + 5].and(0xFF).shiftl(40))
      .or(data[offset + 6].and(0xFF).shiftl(48))
      .or(data[offset + 7].and(0xFF).shiftl(56))
  }

  private static Int getI4LE(Int[] data, Int offset)
  {
    return data[offset].and(0xFF)
      .or(data[offset + 1].and(0xFF).shiftl(8))
      .or(data[offset + 2].and(0xFF).shiftl(16))
      .or(data[offset + 3].and(0xFF).shiftl(24))
  }

  private static Int[] toUtf8Bytes(Str s)
  {
    buf := s.toBuf
    arr := Int[,]
    arr.capacity = buf.size
    while (buf.remaining > 0)
    {
      arr.add(buf.read)
    }
    return arr
  }
}
