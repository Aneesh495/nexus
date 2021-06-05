**
** NexusBitmap: 64-bit word bitmap supporting high-speed bitwise set operations,
** population counts, and sparse range iteration.
**
class NexusBitmap
{
  private Int[] words

  new make(Int initialWordCount := 16)
  {
    this.words = Int[,].fill(0, initialWordCount.max(1))
  }

  **
  ** Set the bit at bitIndex to 1.
  **
  Void set(Int bitIndex)
  {
    ensureCapacity(bitIndex)
    wordIdx := bitIndex / 64
    bitOffset := bitIndex % 64
    words[wordIdx] = words[wordIdx].or(1.shiftl(bitOffset))
  }

  **
  ** Clear the bit at bitIndex to 0.
  **
  Void clearBit(Int bitIndex)
  {
    wordIdx := bitIndex / 64
    if (wordIdx >= words.size) return
    bitOffset := bitIndex % 64
    words[wordIdx] = words[wordIdx].and(1.shiftl(bitOffset).not)
  }

  **
  ** Query state of bit at bitIndex.
  **
  Bool get(Int bitIndex)
  {
    wordIdx := bitIndex / 64
    if (wordIdx >= words.size) return false
    bitOffset := bitIndex % 64
    return words[wordIdx].and(1.shiftl(bitOffset)) != 0
  }

  **
  ** Total number of set bits (population count / Hamming weight).
  **
  Int cardinality()
  {
    pop := 0
    words.each |w|
    {
      if (w != 0) pop += Bits.popCount(w)
    }
    return pop
  }

  **
  ** Check if bitmap has zero set bits.
  **
  Bool isEmpty()
  {
    return words.all |w| { w == 0 }
  }

  **
  ** Bitwise AND (intersection) with other bitmap in-place.
  **
  NexusBitmap and(NexusBitmap other)
  {
    minWords := words.size.min(other.words.size)
    minWords.times |i|
    {
      words[i] = words[i].and(other.words[i])
    }
    for (i := minWords; i < words.size; ++i)
    {
      words[i] = 0
    }
    return this
  }

  **
  ** Bitwise OR (union) with other bitmap in-place.
  **
  NexusBitmap or(NexusBitmap other)
  {
    if (other.words.size > words.size)
    {
      words.fill(0, other.words.size - words.size)
    }
    other.words.size.times |i|
    {
      words[i] = words[i].or(other.words[i])
    }
    return this
  }

  **
  ** Bitwise XOR (symmetric difference) with other bitmap in-place.
  **
  NexusBitmap xor(NexusBitmap other)
  {
    if (other.words.size > words.size)
    {
      words.fill(0, other.words.size - words.size)
    }
    other.words.size.times |i|
    {
      words[i] = words[i].xor(other.words[i])
    }
    return this
  }

  **
  ** Bitwise AND NOT (difference) with other bitmap in-place.
  **
  NexusBitmap andNot(NexusBitmap other)
  {
    limit := words.size.min(other.words.size)
    limit.times |i|
    {
      words[i] = words[i].and(other.words[i].not)
    }
    return this
  }

  **
  ** Clear all words to zero.
  **
  Void clear()
  {
    for (i := 0; i < words.size; ++i)
    {
      words[i] = 0
    }
  }

  **
  ** Total allocated words.
  **
  Int wordCount() { return words.size }

  private Void ensureCapacity(Int bitIndex)
  {
    requiredWords := (bitIndex / 64) + 1
    if (requiredWords > words.size)
    {
      toAdd := requiredWords - words.size
      words.fill(0, toAdd)
    }
  }
}
