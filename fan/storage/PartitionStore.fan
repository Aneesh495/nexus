**
** PartitionStore: Actor-isolated in-memory storage kernel for a single cluster partition.
**
** Encapsulates:
** - Fast primary lookup via cache-conscious RobinHoodMap
** - Ordered range and prefix indexing via SkipList
** - Adaptive cache admission and victim selection via EvictionPolicy
** - O(1) deadline expiration via hierarchical TimingWheel
** - Telemetry: hit/miss counters, memory footprint estimation, and eviction metrics
**
class PartitionStore
{
  const Int partitionId
  private RobinHoodMap map
  private SkipList index
  private EvictionPolicy evictionPolicy
  private TimingWheel timingWheel
  private Int maxEntries
  private Int maxCostBytes

  private Int hits := 0
  private Int misses := 0
  private Int evictions := 0
  private Int totalBytes := 0

  **
  ** Create partition store with given ID, maximum entries, and eviction policy.
  **
  new make(
    Int partitionId,
    Int maxEntries := 10_000,
    Int maxCostBytes := 64 * 1024 * 1024,
    EvictionPolicy? customPolicy := null)
  {
    this.partitionId    = partitionId
    this.maxEntries     = maxEntries.max(16)
    this.maxCostBytes   = maxCostBytes.max(1024)
    this.map            = RobinHoodMap(64)
    this.index          = SkipList(partitionId * 31 + 17)
    this.evictionPolicy = customPolicy != null ? customPolicy : WindowTinyLfuPolicy(this.maxEntries)
    this.timingWheel    = TimingWheel(DateTime.now.toJava)
  }

  **
  ** Retrieve cached entry for key, or null if missing/expired.
  **
  CacheEntry? get(Str key, Int nowMillis := DateTime.now.toJava)
  {
    entry := (CacheEntry?)map.get(key)
    if (entry == null)
    {
      misses++
      return null
    }

    if (entry.isExpired(nowMillis))
    {
      remove(key)
      misses++
      return null
    }

    hits++
    entry.touch(nowMillis)
    evictionPolicy.recordAccess(entry)
    return entry
  }

  **
  ** Insert or overwrite entry. Triggers eviction if capacity limits are breached.
  **
  CacheEntry put(
    Str key,
    Obj? val,
    Int ttlMillis := 0,
    HybridLogicalClock? version := null,
    Int nowMillis := DateTime.now.toJava)
  {
    ver := version != null ? version : HybridLogicalClock(nowMillis, 0)
    newEntry := CacheEntry(key, val, ver, ttlMillis, nowMillis)

    oldObj := map.put(key, newEntry)
    if (oldObj != null)
    {
      oldEntry := (CacheEntry)oldObj
      totalBytes -= oldEntry.costBytes
      timingWheel.cancel(key)
    }

    totalBytes += newEntry.costBytes
    index.put(key, newEntry)
    evictionPolicy.recordInsert(newEntry)

    if (ttlMillis > 0)
    {
      timingWheel.schedule(key, newEntry.expireTime)
    }

    ensureCapacity
    return newEntry
  }

  **
  ** Put entry only if key does not already exist (or is expired).
  **
  CacheEntry? putIfAbsent(
    Str key,
    Obj? val,
    Int ttlMillis := 0,
    HybridLogicalClock? version := null,
    Int nowMillis := DateTime.now.toJava)
  {
    existing := get(key, nowMillis)
    if (existing != null) return null
    return put(key, val, ttlMillis, version, nowMillis)
  }

  **
  ** Remove entry by key. Returns removed entry or null.
  **
  CacheEntry? remove(Str key)
  {
    oldObj := map.remove(key)
    if (oldObj == null) return null

    oldEntry := (CacheEntry)oldObj
    totalBytes -= oldEntry.costBytes
    index.remove(key)
    timingWheel.cancel(key)
    evictionPolicy.recordRemove(oldEntry)
    return oldEntry
  }

  **
  ** Check if key exists and is unexpired.
  **
  Bool containsKey(Str key, Int nowMillis := DateTime.now.toJava)
  {
    return get(key, nowMillis) != null
  }

  **
  ** Evict all expired keys based on hierarchical timing wheel advance.
  **
  Int evictExpired(Int nowMillis := DateTime.now.toJava)
  {
    expiredKeys := timingWheel.advance(nowMillis)
    count := 0
    for (i := 0; i < expiredKeys.size; ++i)
    {
      k := expiredKeys[i]
      if (remove(k) != null) count++
    }
    return count
  }

  **
  ** Range query over sorted keys within [fromKey, toKey).
  **
  Str:CacheEntry range(Str fromKey, Str toKey, Int limit := 100)
  {
    raw := index.range(fromKey, toKey, limit)
    result := Str:CacheEntry[:]
    raw.each |v, k|
    {
      if (v != null) result[k] = (CacheEntry)v
    }
    return result
  }

  **
  ** Scan entries with prefix.
  **
  Str:CacheEntry prefixScan(Str prefix, Int limit := 100)
  {
    raw := index.prefixScan(prefix, limit)
    result := Str:CacheEntry[:]
    raw.each |v, k|
    {
      if (v != null) result[k] = (CacheEntry)v
    }
    return result
  }

  **
  ** Total number of active entries in partition.
  **
  Int size() { map.size }

  **
  ** Estimated memory footprint in bytes.
  **
  Int memoryBytes() { totalBytes }

  **
  ** Cumulative hit count.
  **
  Int hitCount() { hits }

  **
  ** Cumulative miss count.
  **
  Int missCount() { misses }

  **
  ** Cumulative eviction count.
  **
  Int evictionCount() { evictions }

  **
  ** Clear all partition data.
  **
  Void clear()
  {
    map.clear
    index = SkipList(partitionId * 31 + 17)
    evictionPolicy.clear
    timingWheel.clear
    totalBytes = 0
  }

  private Void ensureCapacity()
  {
    while (map.size > maxEntries || totalBytes > maxCostBytes)
    {
      victimKey := evictionPolicy.evictNext
      if (victimKey == null) break

      oldObj := map.remove(victimKey)
      if (oldObj != null)
      {
        oldEntry := (CacheEntry)oldObj
        totalBytes -= oldEntry.costBytes
        index.remove(victimKey)
        timingWheel.cancel(victimKey)
        evictions++
      }
    }
  }
}
