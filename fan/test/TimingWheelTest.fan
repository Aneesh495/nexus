**
** Unit tests for hierarchical TimingWheel expiration.
**
class TimingWheelTest : Test
{
  Void testShortWheel0Timers()
  {
    t0 := 10_000
    wheel := TimingWheel(t0)

    wheel.schedule("keyA", t0 + 50)  // Expires at +50ms
    wheel.schedule("keyB", t0 + 100) // Expires at +100ms
    wheel.schedule("keyC", t0 + 200) // Expires at +200ms

    verifyEq(wheel.size, 3)

    // Advance to +40ms: none expired
    exp1 := wheel.advance(t0 + 40)
    verifyEq(exp1.size, 0)

    // Advance to +60ms: keyA expired
    exp2 := wheel.advance(t0 + 60)
    verifyEq(exp2.size, 1)
    verifyEq(exp2[0], "keyA")

    // Advance to +150ms: keyB expired
    exp3 := wheel.advance(t0 + 150)
    verifyEq(exp3.size, 1)
    verifyEq(exp3[0], "keyB")

    // Advance to +250ms: keyC expired
    exp4 := wheel.advance(t0 + 250)
    verifyEq(exp4.size, 1)
    verifyEq(exp4[0], "keyC")

    verifyEq(wheel.size, 0)
  }

  Void testCancellation()
  {
    t0 := 1000
    wheel := TimingWheel(t0)

    wheel.schedule("cancelMe", t0 + 100)
    verifyEq(wheel.size, 1)

    cancelled := wheel.cancel("cancelMe")
    verifyEq(cancelled, true)
    verifyEq(wheel.size, 0)

    // Advance past deadline: should yield no expired keys
    exp := wheel.advance(t0 + 200)
    verifyEq(exp.size, 0)
  }

  Void testCoarseWheelCascading()
  {
    t0 := 0
    wheel := TimingWheel(t0)

    // Level 1 timer (expires at 6,000ms > tick1Millis of 5120ms)
    wheel.schedule("longTimer", 6000)
    verifyEq(wheel.size, 1)

    // Advance to 5110ms: not expired
    verifyEq(wheel.advance(5110).size, 0)

    // Advance past 6000ms: cascades and expires
    exp := wheel.advance(6050)
    verify(exp.contains("longTimer"))
    verifyEq(wheel.size, 0)
  }
}
