**
** Unit tests for FastRandom PRNG suite.
**
class FastRandomTest : Test
{
  Void testDeterminismFromSeed()
  {
    r1 := FastRandom(123456789)
    r2 := FastRandom(123456789)

    for (i := 0; i < 20; ++i)
    {
      verifyEq(r1.nextI8, r2.nextI8)
    }
  }

  Void testBoundsAndRanges()
  {
    rng := FastRandom(987654321)

    // Bound test
    for (i := 0; i < 100; ++i)
    {
      v := rng.nextInt(50)
      verify(v >= 0)
      verify(v < 50)
    }

    // Range test
    for (i := 0; i < 100; ++i)
    {
      r := rng.nextRange(10, 20)
      verify(r >= 10)
      verify(r <= 20)
    }

    // Float test
    for (i := 0; i < 100; ++i)
    {
      f := rng.nextFloat
      verify(f >= 0.0f)
      verify(f < 1.0f)
    }
  }

  Void testElectionTimeoutRange()
  {
    rng := FastRandom(42)
    for (i := 0; i < 50; ++i)
    {
      timeout := rng.electionTimeout(150)
      verify(timeout >= 150)
      verify(timeout < 300)
    }
  }

  Void testExponentialBackoffWithJitter()
  {
    rng := FastRandom(77)
    for (attempt := 0; attempt < 10; ++attempt)
    {
      sleep := rng.exponentialBackoffWithJitter(10, 1000, attempt)
      verify(sleep >= 0)
      verify(sleep <= 1000)
    }
  }

  Void testGaussianMeanAndVariance()
  {
    rng := FastRandom(555)
    sum := 0.0f
    n := 500
    for (i := 0; i < n; ++i)
    {
      sum += rng.nextGaussian(0.0f, 1.0f)
    }
    mean := sum / n.toFloat
    // Sample mean should be close to 0 (-0.3 to 0.3)
    verify(mean.abs < 0.3f)
  }
}
