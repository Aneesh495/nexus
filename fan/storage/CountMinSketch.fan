**
** CountMinSketch: 4-bit saturated frequency estimator with periodic halving reset.
**
** Reference:
** Cormode & Muthukrishnan, "An Improved Data Stream Summary: The Count-Min Sketch", 2005.
** Einziger et al., "TinyLFU: A Highly Efficient Cache Admission Policy", ACM TOS 2017.
**
** Structure:
** - 4 independent hash tables with 4-bit counters (0..15).
** - Packed 16 counters per 64-bit word for maximum memory efficiency.
** - Parallel bitwise aging: when sample count reaches sampleSize, all counters are halved.
**
class CountMinSketch
{
  private Int[] table
  private Int tableMask
  private Int sampleSize
  private Int additions := 0

  **
  ** Create sketch with target capacity. Width is rounded to next power of two.
  **
  new make(Int targetCapacity)
  {
    width := Bits.nextPowerOfTwo(targetCapacity.max(64))
    // 4 tables of 'width' 4-bit counters. Total counters = 4 * width.
    // Each 64-bit Int holds 16 counters.
    wordsNeeded := (width * 4).shiftr(4).max(16)
    this.table = Int[,].fill(0, wordsNeeded)
    this.tableMask = width - 1
    this.sampleSize = (targetCapacity * 10).max(1000)
  }

  **
  ** Increment frequency count for a key. Returns estimated frequency after increment.
  **
  Int increment(Str key)
  {
    hashes := HashUtils.murmur3_128(toUtf8Bytes(key), 0)
    h1 := hashes[0]
    h2 := hashes[1]

    minCount := 15

    for (i := 0; i < 4; ++i)
    {
      idx := (h1 + i * h2).and(0x7FFFFFFFFFFFFFFF).and(tableMask)
      tableIdx := i * (tableMask + 1) + idx
      curr := getCounter(tableIdx)

      if (curr < 15)
      {
        setCounter(tableIdx, curr + 1)
        if (curr + 1 < minCount) minCount = curr + 1
      }
      else
      {
        if (curr < minCount) minCount = curr
      }
    }

    additions++
    if (additions >= sampleSize)
    {
      resetHalving
      additions = 0
    }

    return minCount
  }

  **
  ** Estimate frequency for a key. Returns minimum across the 4 hash counters (0..15).
  **
  Int estimate(Str key)
  {
    hashes := HashUtils.murmur3_128(toUtf8Bytes(key), 0)
    h1 := hashes[0]
    h2 := hashes[1]

    minCount := 15

    for (i := 0; i < 4; ++i)
    {
      idx := (h1 + i * h2).and(0x7FFFFFFFFFFFFFFF).and(tableMask)
      tableIdx := i * (tableMask + 1) + idx
      c := getCounter(tableIdx)
      if (c < minCount) minCount = c
    }

    return minCount
  }

  **
  ** Halve all 4-bit counters across the sketch in parallel using bitwise arithmetic.
  **
  Void resetHalving()
  {
    mask := 0x7777777777777777
    for (i := 0; i < table.size; ++i)
    {
      w := table[i]
      table[i] = w.shiftr(1).and(mask)
    }
  }

  **
  ** Clear all counters.
  **
  Void clear()
  {
    for (i := 0; i < table.size; ++i)
    {
      table[i] = 0
    }
    additions = 0
  }

  private Int getCounter(Int counterIndex)
  {
    wordIdx := counterIndex.shiftr(4)
    slotIdx := counterIndex.and(15)
    shift := slotIdx.shiftl(2)
    return table[wordIdx].shiftr(shift).and(0xF)
  }

  private Void setCounter(Int counterIndex, Int val)
  {
    wordIdx := counterIndex.shiftr(4)
    slotIdx := counterIndex.and(15)
    shift := slotIdx.shiftl(2)

    word := table[wordIdx]
    clearMask := (0xF.shiftl(shift)).not
    word = word.and(clearMask).or((val.and(0xF)).shiftl(shift))
    table[wordIdx] = word
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
