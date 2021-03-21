**
** Unit tests for CountMinSketch 4-bit frequency estimator.
**
class CountMinSketchTest : Test
{
  Void testIncrementAndEstimation()
  {
    sketch := CountMinSketch(256)
    verifyEq(sketch.estimate("keyA"), 0)
    verifyEq(sketch.estimate("keyB"), 0)

    sketch.increment("keyA")
    sketch.increment("keyA")
    sketch.increment("keyA")

    sketch.increment("keyB")

    verifyEq(sketch.estimate("keyA"), 3)
    verifyEq(sketch.estimate("keyB"), 1)
    verifyEq(sketch.estimate("unseenKey"), 0)
  }

  Void testSaturationAt15()
  {
    sketch := CountMinSketch(128)
    for (i := 0; i < 25; ++i)
    {
      sketch.increment("hotKey")
    }

    // 4-bit saturated counter must clamp at 15
    verifyEq(sketch.estimate("hotKey"), 15)
  }

  Void testHalvingAging()
  {
    sketch := CountMinSketch(128)
    for (i := 0; i < 10; ++i)
    {
      sketch.increment("agingKey")
    }
    verifyEq(sketch.estimate("agingKey"), 10)

    // Trigger halving
    sketch.resetHalving

    // 10 halved is 5
    verifyEq(sketch.estimate("agingKey"), 5)

    sketch.resetHalving
    // 5 halved is 2
    verifyEq(sketch.estimate("agingKey"), 2)
  }
}
