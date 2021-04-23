**
** Unit tests for PhiFailureDetector accrual failure detection.
**
class FailureDetectorTest : Test
{
  Void testBootstrapPhase()
  {
    fd := PhiFailureDetector(8.0f, 50.0f)
    t0 := 1000

    // Initial heartbeat
    fd.heartbeat("node-1", t0)

    // With fewer than 5 samples, should report phi = 0 for short delays
    verifyEq(fd.phi("node-1", t0 + 200), 0.0f)
    verifyTrue(fd.isAvailable("node-1", t0 + 200))

    // Delay > 10s kicks in bootstrap fallback
    verifyEq(fd.phi("node-1", t0 + 15_000), 12.0f)
    verifyFalse(fd.isAvailable("node-1", t0 + 15_000))
  }

  Void testSteadyHeartbeats()
  {
    fd := PhiFailureDetector(8.0f, 50.0f)
    t := 1000

    // Send 20 heartbeats every 100ms
    20.times |i|
    {
      t += 100
      fd.heartbeat("node-2", t)
    }

    // At t + 100ms, phi should be small
    phiAtNormal := fd.phi("node-2", t + 100)
    verifyTrue(phiAtNormal < 2.0f)
    verifyTrue(fd.isAvailable("node-2", t + 100))

    // At t + 1000ms (10x normal interval), phi should exceed threshold
    phiAtDelay := fd.phi("node-2", t + 1000)
    verifyTrue(phiAtDelay > 8.0f)
    verifyFalse(fd.isAvailable("node-2", t + 1000))
  }

  Void testPhiMonotonicGrowth()
  {
    fd := PhiFailureDetector(8.0f, 100.0f)
    t := 1000

    // 15 heartbeats every 100ms
    15.times |i|
    {
      t += 100
      fd.heartbeat("node-3", t)
    }

    p1 := fd.phi("node-3", t + 150)
    p2 := fd.phi("node-3", t + 250)
    p3 := fd.phi("node-3", t + 400)
    p4 := fd.phi("node-3", t + 600)

    verifyTrue(p2 > p1)
    verifyTrue(p3 > p2)
    verifyTrue(p4 > p3)
  }

  Void testNodeRemoval()
  {
    fd := PhiFailureDetector(8.0f, 50.0f)
    fd.heartbeat("node-4", 1000)
    verifyEq(fd.phi("node-4", 1200), 0.0f)

    fd.remove("node-4")
    verifyEq(fd.phi("node-4", 1200), 0.0f)
  }
}
