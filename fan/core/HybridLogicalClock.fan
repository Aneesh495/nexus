using concurrent

**
** HybridLogicalClock (HLC): Combines physical wall-clock time with Lamport logical
** counters to provide strictly monotonic, causally consistent timestamps.
**
** Reference:
** Kulkarni et al., "Logical Physical Clocks and Consistent Snapshots in Globally
** Distributed Databases", IEEE TPDS 2014.
**
** Invariants:
** 1. Monotonicity: For any events e -> e', HLC(e) < HLC(e').
** 2. Bounded Physical Drift: |hlc.l - physicalTime| <= maxDriftMillis.
**
const class HybridLogicalClock
{
  ** Physical wall-clock component in milliseconds since Unix epoch
  const Int physical

  ** Logical sequence component for sub-millisecond tie-breaking
  const Int logical

  ** Maximum permitted physical clock drift in milliseconds (default: 60,000 ms)
  static const Int maxDriftMillis := 60_000

  **
  ** Construct an HLC instance with given physical time and logical counter.
  **
  new make(Int physical, Int logical)
  {
    this.physical = physical
    this.logical  = logical
  }

  **
  ** Create the zero/initial clock timestamp.
  **
  static HybridLogicalClock zero()
  {
    return HybridLogicalClock(0, 0)
  }

  **
  ** Create an HLC timestamp from the current system wall clock.
  **
  static HybridLogicalClock now()
  {
    return HybridLogicalClock(DateTime.now.toJava, 0)
  }

  **
  ** Advance clock for a local event given the current physical time.
  **
  HybridLogicalClock send(Int currentPhysicalTime := DateTime.now.toJava)
  {
    lPrime := physical.max(currentPhysicalTime)
    cPrime := 0

    if (lPrime == physical)
    {
      cPrime = logical + 1
    }
    else
    {
      cPrime = 0
    }

    return HybridLogicalClock(lPrime, cPrime)
  }

  **
  ** Update clock upon receiving a remote message carrying remoteTimestamp.
  ** Enforces causal ordering while rejecting timestamps with excessive drift.
  **
  HybridLogicalClock receive(HybridLogicalClock remote, Int currentPhysicalTime := DateTime.now.toJava)
  {
    // Clock drift guard
    drift := remote.physical - currentPhysicalTime
    if (drift > maxDriftMillis)
    {
      throw Err("Clock drift exceeded limit: drift=${drift}ms, max=${maxDriftMillis}ms")
    }

    lPrime := physical.max(remote.physical).max(currentPhysicalTime)
    cPrime := 0

    if (lPrime == physical && lPrime == remote.physical)
    {
      cPrime = logical.max(remote.logical) + 1
    }
    else if (lPrime == physical)
    {
      cPrime = logical + 1
    }
    else if (lPrime == remote.physical)
    {
      cPrime = remote.logical + 1
    }
    else
    {
      cPrime = 0
    }

    return HybridLogicalClock(lPrime, cPrime)
  }

  **
  ** Encode HLC into a 64-bit integer assuming physical fits in 48 bits and logical in 16 bits.
  **
  Int toCompactBits()
  {
    p48 := physical.and(0x0000FFFFFFFFFFFF)
    l16 := logical.and(0xFFFF)
    return p48.shiftl(16).or(l16)
  }

  **
  ** Decode HLC from compact 64-bit integer representation.
  **
  static HybridLogicalClock fromCompactBits(Int bits)
  {
    p := bits.shiftr(16).and(0x0000FFFFFFFFFFFF)
    c := bits.and(0xFFFF)
    return HybridLogicalClock(p, c)
  }

  override Int compare(Obj that)
  {
    other := (HybridLogicalClock)that
    if (this.physical != other.physical)
      return this.physical <=> other.physical
    return this.logical <=> other.logical
  }

  override Bool equals(Obj? that)
  {
    if (that isnot HybridLogicalClock) return false
    other := (HybridLogicalClock)that
    return this.physical == other.physical && this.logical == other.logical
  }

  override Int hash()
  {
    return physical.xor(logical.shiftl(32))
  }

  override Str toStr()
  {
    return "HLC($physical:$logical)"
  }
}
