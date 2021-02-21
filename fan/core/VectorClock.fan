**
** Causal relation between vector clocks.
**
enum class VcRelation
{
  before,
  after,
  equal,
  concurrent
}

**
** VectorClock: Tracks causal ordering and concurrent updates across cluster nodes.
**
** Supports:
** - Incremental node ticks.
** - Upper semi-lattice merge (element-wise supremum).
** - Four-way comparison: BEFORE, AFTER, EQUAL, CONCURRENT.
**
const class VectorClock
{
  ** Node to version mapping
  const Str:Int versions

  **
  ** Create empty vector clock.
  **
  new make(Str:Int versions := Str:Int[:])
  {
    this.versions = versions.toImmutable
  }

  **
  ** Increment version counter for specified node ID.
  **
  VectorClock increment(Str nodeId)
  {
    copy := versions.dup
    curr := copy.get(nodeId, 0)
    copy[nodeId] = curr + 1
    return VectorClock(copy)
  }

  **
  ** Merge this clock with another by taking component-wise maximum.
  **
  VectorClock merge(VectorClock other)
  {
    merged := versions.dup
    other.versions.each |v, k|
    {
      curr := merged.get(k, 0)
      if (v > curr) merged[k] = v
    }
    return VectorClock(merged)
  }

  **
  ** Compare causal relation with another vector clock.
  **
  VcRelation compareCausality(VectorClock other)
  {
    hasGreater := false
    hasLesser  := false

    allKeys := Str:Bool[:]
    versions.each |_, k| { allKeys[k] = true }
    other.versions.each |_, k| { allKeys[k] = true }

    allKeys.each |_, k|
    {
      v1 := versions.get(k, 0)
      v2 := other.versions.get(k, 0)

      if (v1 > v2) hasGreater = true
      if (v1 < v2) hasLesser  = true
    }

    if (!hasGreater && !hasLesser) return VcRelation.equal
    if (hasGreater && !hasLesser)  return VcRelation.after
    if (!hasGreater && hasLesser)  return VcRelation.before
    return VcRelation.concurrent
  }

  **
  ** Get counter for specific node ID.
  **
  Int get(Str nodeId)
  {
    return versions.get(nodeId, 0)
  }

  override Bool equals(Obj? that)
  {
    if (that isnot VectorClock) return false
    return compareCausality((VectorClock)that) == VcRelation.equal
  }

  override Int hash()
  {
    h := 17
    versions.each |v, k| { h = 31 * h + k.hash + v }
    return h
  }

  override Str toStr()
  {
    sb := StrBuf().add("VC{")
    first := true
    versions.each |v, k|
    {
      if (!first) sb.add(", ")
      sb.add("$k:$v")
      first = false
    }
    return sb.add("}").toStr
  }
}
