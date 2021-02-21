**
** Unit tests for HybridLogicalClock and VectorClock.
**
class HlcTest : Test
{
  Void testHlcMonotonicLocal()
  {
    t0 := 1000
    h1 := HybridLogicalClock(t0, 0)
    h2 := h1.send(t0)
    h3 := h2.send(t0)

    verifyEq(h1.physical, t0)
    verifyEq(h1.logical, 0)

    verifyEq(h2.physical, t0)
    verifyEq(h2.logical, 1)

    verifyEq(h3.physical, t0)
    verifyEq(h3.logical, 2)

    verify(h1 < h2)
    verify(h2 < h3)

    // Advance physical time
    t1 := 1050
    h4 := h3.send(t1)
    verifyEq(h4.physical, t1)
    verifyEq(h4.logical, 0)
    verify(h3 < h4)
  }

  Void testHlcReceiveCausality()
  {
    localClock := HybridLogicalClock(2000, 5)
    remoteClock := HybridLogicalClock(2050, 2)

    // Receive at physical time 2010
    updated := localClock.receive(remoteClock, 2010)

    verifyEq(updated.physical, 2050)
    verifyEq(updated.logical, 3)
    verify(updated > localClock)
    verify(updated > remoteClock)
  }

  Void testHlcClockDriftRejection()
  {
    localClock := HybridLogicalClock(1000, 0)
    // 70,000ms in the future (> 60,000ms maxDrift)
    futureClock := HybridLogicalClock(1000 + 70_000, 0)

    verifyErr(Err#)
    {
      localClock.receive(futureClock, 1000)
    }
  }

  Void testHlcCompactEncoding()
  {
    hlc := HybridLogicalClock(1730553600000, 42)
    bits := hlc.toCompactBits
    decoded := HybridLogicalClock.fromCompactBits(bits)

    verifyEq(hlc.physical, decoded.physical)
    verifyEq(hlc.logical, decoded.logical)
    verifyEq(hlc, decoded)
  }

  Void testVectorClockCausality()
  {
    vc0 := VectorClock()
    vcA1 := vc0.increment("nodeA")
    vcA2 := vcA1.increment("nodeA")
    vcB1 := vc0.increment("nodeB")

    verifyEq(vcA1.compareCausality(vcA2), VcRelation.before)
    verifyEq(vcA2.compareCausality(vcA1), VcRelation.after)
    verifyEq(vcA1.compareCausality(vcB1), VcRelation.concurrent)

    merged := vcA2.merge(vcB1)
    verifyEq(merged.get("nodeA"), 2)
    verifyEq(merged.get("nodeB"), 1)
    verifyEq(vcA2.compareCausality(merged), VcRelation.before)
    verifyEq(vcB1.compareCausality(merged), VcRelation.before)
  }
}
