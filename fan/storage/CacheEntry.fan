**
** CacheEntry: Core storage cell tracking cached payload, causal versioning,
** expiration deadlines, and access telemetry.
**
** Flag Masks:
** - 0x01: Tombstone (soft-deleted in MVCC / WAL stream)
** - 0x02: Dirty (pending flush in write-behind queue)
** - 0x04: Locked (acquired by distributed lock or active 2PC transaction)
**
class CacheEntry
{
  static const Int flagTombstone := 0x01
  static const Int flagDirty     := 0x02
  static const Int flagLocked    := 0x04

  Str key
  Obj? val
  HybridLogicalClock version
  Int createTime
  Int lastAccessTime
  Int expireTime // 0 means immortal
  Int accessCount := 1
  Int costBytes := 0
  Int flags := 0

  **
  ** Create a new cache entry.
  **
  new make(
    Str key,
    Obj? val,
    HybridLogicalClock version,
    Int ttlMillis := 0,
    Int nowMillis := DateTime.now.toJava)
  {
    this.key            = key
    this.val            = val
    this.version        = version
    this.createTime     = nowMillis
    this.lastAccessTime = nowMillis
    this.expireTime     = (ttlMillis > 0) ? (nowMillis + ttlMillis) : 0
    this.costBytes      = estimateCost(key, val)
    this.flags          = 0
  }

  **
  ** Check if the entry has expired relative to reference timestamp.
  **
  Bool isExpired(Int nowMillis := DateTime.now.toJava)
  {
    return expireTime > 0 && nowMillis >= expireTime
  }

  **
  ** Check if entry is a tombstone marker.
  **
  Bool isTombstone()
  {
    return flags.and(flagTombstone) != 0
  }

  **
  ** Check if entry is marked dirty for write-behind persistence.
  **
  Bool isDirty()
  {
    return flags.and(flagDirty) != 0
  }

  **
  ** Check if entry is currently locked by a transaction.
  **
  Bool isLocked()
  {
    return flags.and(flagLocked) != 0
  }

  **
  ** Mark or unmark tombstone flag.
  **
  This setTombstone(Bool tombstone)
  {
    if (tombstone) flags = flags.or(flagTombstone)
    else           flags = flags.and(flagTombstone.not)
    return this
  }

  **
  ** Mark or unmark dirty flag.
  **
  This setDirty(Bool dirty)
  {
    if (dirty) flags = flags.or(flagDirty)
    else       flags = flags.and(flagDirty.not)
    return this
  }

  **
  ** Mark or unmark locked flag.
  **
  This setLocked(Bool locked)
  {
    if (locked) flags = flags.or(flagLocked)
    else        flags = flags.and(flagLocked.not)
    return this
  }

  **
  ** Record access to update telemetry.
  **
  This touch(Int nowMillis := DateTime.now.toJava)
  {
    this.lastAccessTime = nowMillis
    this.accessCount++
    return this
  }

  **
  ** Estimate memory footprint of key and value in bytes.
  **
  static Int estimateCost(Str key, Obj? val)
  {
    // Object overhead: 48 bytes base entry
    cost := 48 + key.size * 2
    if (val == null) return cost

    if (val is Str)
    {
      cost += 24 + ((Str)val).size * 2
    }
    else if (val is Int || val is Float)
    {
      cost += 16
    }
    else if (val is ByteBuf)
    {
      cost += 32 + ((ByteBuf)val).readableBytes
    }
    else if (val is List)
    {
      cost += 32 + ((List)val).size * 16
    }
    else if (val is Map)
    {
      cost += 64 + ((Map)val).size * 32
    }
    else
    {
      cost += 64
    }
    return cost
  }

  override Str toStr()
  {
    return "CacheEntry(k=$key, ver=$version, exp=$expireTime, cost=$costBytes, flags=0x${flags.toHex})"
  }
}
