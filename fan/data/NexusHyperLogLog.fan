**
** NexusHyperLogLog: Probabilistic cardinality estimator using 64-bit hash values,
** harmonic mean aggregation, and linear counting bias correction.
**
** Reference:
** Flajolet, Fusy, Gandouet, Meunier, "HyperLogLog: the analysis of a near-optimal cardinality estimation algorithm",
** AOFA 2007; Heule, Nunkesser, Hall, "HyperLogLog in Practice: Algorithmic Engineering of a State of The Art Cardinality Estimation Algorithm",
** EDBT 2013.
**
class NexusHyperLogLog
{
  private Int p
  private Int m
  private Float alphaM
  private Int[] registers

  **
  ** Create HyperLogLog with precision p (default 12 -> 4096 registers, ~1.6% relative error).
  **
  new make(Int precision := 12)
  {
    if (precision < 4 || precision > 16) throw ArgErr("Precision must be between 4 and 16: $precision")
    this.p = precision
    this.m = 1.shiftl(precision)
    this.registers = Int[,].fill(0, m)
    this.alphaM = computeAlpha(m)
  }

  **
  ** Number of register buckets: m = 2^p.
  **
  Int bucketCount() { return m }

  **
  ** Precision bits.
  **
  Int precision() { return p }

  **
  ** Add a string element to the estimator.
  **
  Void add(Str element)
  {
    hash := HashUtils.murmur3_64Str(element)
    addHash(hash)
  }

  **
  ** Ingest 64-bit hash value directly.
  **
  Void addHash(Int hash)
  {
    // Extract register index from upper p bits
    idx := hash.shiftr(64 - p).and(m - 1)

    // Remaining bits for leading zero counting
    remaining := hash.shiftl(p)
    lz := (remaining == 0) ? (64 - p) : Bits.numberOfLeadingZeros(remaining)
    rank := lz + 1

    if (rank > registers[idx])
    {
      registers[idx] = rank
    }
  }

  **
  ** Compute estimated distinct element cardinality.
  **
  Int estimate()
  {
    sum := 0.0f
    zeroBuckets := 0

    registers.each |val|
    {
      sum += (1.0f / 2.0f.pow(val.toFloat))
      if (val == 0) zeroBuckets++
    }

    rawEstimate := alphaM * (m.toFloat * m.toFloat) / sum

    // Small range correction: Linear Counting when rawEstimate <= 2.5 * m
    if (rawEstimate <= 2.5f * m.toFloat)
    {
      if (zeroBuckets > 0)
      {
        return (m.toFloat * (m.toFloat / zeroBuckets.toFloat).log).round.toInt
      }
    }

    return rawEstimate.round.toInt
  }

  **
  ** Merge another compatible HyperLogLog estimator into this instance in-place.
  **
  Void merge(NexusHyperLogLog other)
  {
    if (other.p != this.p) throw ArgErr("Cannot merge HLL with different precision: $other.p != $this.p")
    m.times |i|
    {
      if (other.registers[i] > this.registers[i])
      {
        this.registers[i] = other.registers[i]
      }
    }
  }

  **
  ** Clear all registers back to zero.
  **
  Void clear()
  {
    registers.fill(0, m)
  }

  private static Float computeAlpha(Int m)
  {
    if (m == 16) return 0.673f
    if (m == 32) return 0.697f
    if (m == 64) return 0.709f
    return 0.7213f / (1.0f + 1.079f / m.toFloat)
  }
}
