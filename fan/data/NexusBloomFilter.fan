**
** NexusBloomFilter: Probabilistic set membership filter utilizing Kirsch-Mitzenmacher
** dual-hash technique to produce k hashes from Murmur3 and CityHash.
**
** Reference:
** Kirsch and Mitzenmacher, "Less Hashing, Same Performance: Building a Better Bloom Filter",
** ESA 2006.
**
class NexusBloomFilter
{
  private Int expectedInsertions
  private Float fpp
  private Int numBits
  private Int numHashes
  private Int count := 0
  private Int[] words

  **
  ** Create Bloom filter configured for expectedInsertions and target false positive probability.
  **
  new make(Int expectedInsertions := 10_000, Float targetFpp := 0.01f)
  {
    if (expectedInsertions <= 0) throw ArgErr("Expected insertions must be positive: $expectedInsertions")
    if (targetFpp <= 0.0f || targetFpp >= 1.0f) throw ArgErr("Target FPP must be in (0, 1): $targetFpp")

    this.expectedInsertions = expectedInsertions
    this.fpp = targetFpp

    // Optimal bit size: m = -n * ln(p) / (ln(2)^2)
    ln2 := 2.0f.log
    mFloat := -expectedInsertions.toFloat * targetFpp.log / (ln2 * ln2)
    this.numBits = mFloat.round.toInt.max(64)

    // Optimal hash functions count: k = (m / n) * ln(2)
    kFloat := (numBits.toFloat / expectedInsertions.toFloat) * ln2
    this.numHashes = kFloat.round.toInt.max(1).min(30)

    numWords := (numBits + 63) / 64
    this.words = Int[,].fill(0, numWords)
  }

  **
  ** Total number of bits allocated.
  **
  Int bitCount() { return numBits }

  **
  ** Number of hash functions evaluated per element.
  **
  Int hashCount() { return numHashes }

  **
  ** Total elements added to the filter.
  **
  Int size() { return count }

  **
  ** Add element to the Bloom filter.
  **
  Void add(Str element)
  {
    h1 := HashUtils.murmur3_64Str(element)
    h2 := HashUtils.fnv1a_64Str(element)

    for (i := 0; i < numHashes; ++i)
    {
      combined := h1 + i * h2
      bitIdx := combined.and(0x7FFFFFFFFFFFFFFF) % numBits
      setBit(bitIdx)
    }
    count++
  }

  **
  ** Test whether element might be in the set (never produces false negatives).
  **
  Bool mightContain(Str element)
  {
    h1 := HashUtils.murmur3_64Str(element)
    h2 := HashUtils.fnv1a_64Str(element)

    for (i := 0; i < numHashes; ++i)
    {
      combined := h1 + i * h2
      bitIdx := combined.and(0x7FFFFFFFFFFFFFFF) % numBits
      if (!getBit(bitIdx))
      {
        return false
      }
    }
    return true
  }

  **
  ** Theoretical false positive probability based on current fill count.
  **
  Float expectedFpp()
  {
    // (1 - e^(-k * n / m))^k
    exponent := -numHashes.toFloat * count.toFloat / numBits.toFloat
    probOneBit := 1.0f - exponent.exp
    return probOneBit.pow(numHashes.toFloat)
  }

  **
  ** Clear all bits.
  **
  Void clear()
  {
    for (i := 0; i < words.size; ++i)
    {
      words[i] = 0
    }
    count = 0
  }

  private Void setBit(Int bitIndex)
  {
    wordIdx := bitIndex / 64
    bitOffset := bitIndex % 64
    words[wordIdx] = words[wordIdx].or(1.shiftl(bitOffset))
  }

  private Bool getBit(Int bitIndex)
  {
    wordIdx := bitIndex / 64
    bitOffset := bitIndex % 64
    return words[wordIdx].and(1.shiftl(bitOffset)) != 0
  }
}
