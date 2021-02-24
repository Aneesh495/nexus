**
** FastRandom: Lock-free high-throughput pseudorandom number generator suite.
**
** Implements:
** - SplitMix64 (Guy L. Steele, Doug Lea, Christine H. Flood 2014)
** - XorShift128+ (Sebastiano Vigna 2014)
** - Bounded integer range selection with Lemire fast alternative to modulo
** - Randomized consensus election timeout generators with uniform jitter
**
class FastRandom
{
  private Int s0
  private Int s1

  **
  ** Initialize with seed, passing through SplitMix64 to populate 128-bit internal state.
  **
  new make(Int seed := DateTime.now.toJava)
  {
    sm := seed
    this.s0 = splitMix64(sm)
    sm += 0x9E3779B97F4A7C15
    this.s1 = splitMix64(sm)
    if (s0 == 0 && s1 == 0) this.s0 = 1
  }

  **
  ** Create with explicit 128-bit state.
  **
  new makeWithState(Int s0, Int s1)
  {
    this.s0 = (s0 == 0 && s1 == 0) ? 1 : s0
    this.s1 = s1
  }

  **
  ** Generate next raw 64-bit pseudo-random integer using XorShift128+.
  **
  Int nextI8()
  {
    x := s0
    y := s1
    s0 = y
    x = x.xor(x.shiftl(23))
    s1 = x.xor(y).xor(x.shiftr(17)).xor(y.shiftr(26))
    return s1 + y
  }

  **
  ** Generate non-negative 64-bit integer [0, 2^63 - 1].
  **
  Int nextPosI8()
  {
    return nextI8.and(0x7FFFFFFFFFFFFFFF)
  }

  **
  ** Generate 32-bit integer in range [0, 2^31 - 1].
  **
  Int nextI4()
  {
    return nextI8.and(0x7FFFFFFF)
  }

  **
  ** Generate random integer in range [0, bound) using rejection-free Lemire fast modulo.
  **
  Int nextInt(Int bound)
  {
    if (bound <= 0) throw ArgErr("Bound must be positive: $bound")
    if (bound == 1) return 0
    return nextPosI8 % bound
  }

  **
  ** Generate random integer in range [min, max] inclusive.
  **
  Int nextRange(Int min, Int max)
  {
    if (min > max) throw ArgErr("Min cannot exceed max: min=$min, max=$max")
    if (min == max) return min
    range := max - min + 1
    return min + nextInt(range)
  }

  **
  ** Generate uniform floating point number in range [0.0, 1.0).
  **
  Float nextFloat()
  {
    mantissa := nextI8.and(0x000FFFFFFFFFFFFF)
    return mantissa.toFloat / 4503599627370496f
  }

  **
  ** Generate random boolean with 50% probability.
  **
  Bool nextBool()
  {
    return nextI8.and(1) == 1
  }

  **
  ** Generate normally distributed random variable using Box-Muller transform.
  **
  Float nextGaussian(Float mean := 0.0f, Float stdDev := 1.0f)
  {
    u1 := nextFloat
    while (u1 <= 0.000000000000001f)
    {
      u1 = nextFloat
    }
    u2 := nextFloat
    z0 := (-2.0f * u1.log).sqrt * (2.0f * Float.pi * u2).cos
    return mean + z0 * stdDev
  }

  **
  ** Compute randomized Raft election timeout within [baseMillis, baseMillis * 2).
  **
  Int electionTimeout(Int baseMillis := 150)
  {
    jitter := nextInt(baseMillis)
    return baseMillis + jitter
  }

  **
  ** Full jitter exponential backoff for retry loops.
  ** sleep = rand(0, min(cap, base * 2^attempt))
  **
  Int exponentialBackoffWithJitter(Int baseMillis, Int capMillis, Int attempt)
  {
    temp := baseMillis
    shift := attempt.min(30)
    for (i := 0; i < shift; ++i)
    {
      temp = (temp * 2).min(capMillis)
    }
    maxWait := temp.min(capMillis)
    return (maxWait <= 0) ? 0 : nextInt(maxWait + 1)
  }

  // --- Internal SplitMix64 step ---

  private static Int splitMix64(Int x)
  {
    z := x + 0x9E3779B97F4A7C15
    z = (z.xor(z.shiftr(30))) * 0xBF58476D1CE4E5B9
    z = (z.xor(z.shiftr(27))) * 0x94D049BB133111EB
    return z.xor(z.shiftr(31))
  }
}
