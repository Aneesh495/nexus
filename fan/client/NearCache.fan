**
** In-process L1 client-side near cache with LRU eviction and invalidation listeners.
** Dramatically reduces network hops for hot key read operations.
**
class NearCache
{
  private Int maxEntries
  private Int ttlMillis
  private Str:Obj entries := Str:Obj[:]
  private Str:Int expireTimes := Str:Int[:]
  private Str[] accessOrder := Str[,]
  private Int hits := 0
  private Int misses := 0

  new make(Int maxEntries := 10000, Int ttlMillis := 60000)
  {
    this.maxEntries = maxEntries.max(1)
    this.ttlMillis = ttlMillis
  }

  ** Get current entry count in near cache **
  Int size() { entries.size }

  ** Return cache hit count **
  Int hitCount() { hits }

  ** Return cache miss count **
  Int missCount() { misses }

  ** Calculate hit ratio as float between 0.0 and 1.0 **
  Float hitRatio()
  {
    total := hits + misses
    if (total == 0) return 0.0f
    return hits.toFloat / total.toFloat
  }

  ** Retrieve entry from near cache if present and unexpired **
  Obj? get(Str key, Int nowMillis := DateTime.now.toJava)
  {
    if (!entries.containsKey(key))
    {
      misses++
      return null
    }

    exp := expireTimes.get(key, 0)
    if (exp > 0 && nowMillis >= exp)
    {
      // Expired entry: purge
      invalidate(key)
      misses++
      return null
    }

    // Touch LRU access order
    accessOrder.remove(key)
    accessOrder.add(key)
    hits++
    return entries[key]
  }

  ** Store an entry in near cache **
  Void put(Str key, Obj val, Int nowMillis := DateTime.now.toJava)
  {
    // Evict oldest if capacity reached
    while (entries.size >= maxEntries && !entries.containsKey(key))
    {
      if (accessOrder.isEmpty) break
      victim := accessOrder.removeAt(0)
      entries.remove(victim)
      expireTimes.remove(victim)
    }

    entries[key] = val
    expireTimes[key] = ttlMillis > 0 ? nowMillis + ttlMillis : 0

    accessOrder.remove(key)
    accessOrder.add(key)
  }

  ** Invalidate and purge a key from near cache upon remote mutation **
  Void invalidate(Str key)
  {
    entries.remove(key)
    expireTimes.remove(key)
    accessOrder.remove(key)
  }

  ** Clear all entries and reset telemetry **
  Void clear()
  {
    entries.clear
    expireTimes.clear
    accessOrder.clear
    hits = 0
    misses = 0
  }
}
