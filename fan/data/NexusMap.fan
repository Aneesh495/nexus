**
** MapEventType: Mutation classifications for continuous listener events.
**
enum class MapEventType
{
  entry_added,
  entry_updated,
  entry_removed,
  entry_expired
}

**
** NexusMap: High-performance distributed key-value map interface
** with entry processors, TTL expiration, and continuous mutation listeners.
**
class NexusMap
{
  private Str name
  private Int partitionCount
  private Int:PartitionStore partitions := Int:PartitionStore[:]
  private |MapEventType, Str, Obj?, Obj?|[] listeners := |MapEventType, Str, Obj?, Obj?|[,]

  new make(Str name, Int partitionCount := 16)
  {
    this.name           = name
    this.partitionCount = partitionCount
    partitionCount.times |p|
    {
      partitions[p] = PartitionStore(p)
    }
  }

  **
  ** Map identifier name.
  **
  Str mapName() { return name }

  **
  ** Map key to target partition ID.
  **
  Int partitionId(Str key)
  {
    h := HashUtils.murmur3_32Str(key).and(0x7FFFFFFF)
    return h % partitionCount
  }

  **
  ** Retrieve partition store for a key.
  **
  PartitionStore getStore(Str key)
  {
    return partitions[partitionId(key)]
  }

  **
  ** Get value mapped to key. Returns null if missing or expired.
  **
  Obj? get(Str key)
  {
    entry := getStore(key).get(key)
    return entry != null ? entry.val : null
  }

  **
  ** Associate value with key, optionally setting TTL expiration.
  **
  Obj? put(Str key, Obj? val, Int ttlMillis := 0)
  {
    store := getStore(key)
    oldEntry := store.get(key)
    oldVal := oldEntry != null ? oldEntry.val : null

    store.put(key, val, ttlMillis)

    evt := (oldVal == null) ? MapEventType.entry_added : MapEventType.entry_updated
    notifyListeners(evt, key, oldVal, val)
    return oldVal
  }

  **
  ** Put value only if key is not already present.
  ** Returns true if inserted, false if already present.
  **
  Bool putIfAbsent(Str key, Obj? val, Int ttlMillis := 0)
  {
    store := getStore(key)
    existing := store.get(key)
    if (existing != null) return false

    store.put(key, val, ttlMillis)
    notifyListeners(MapEventType.entry_added, key, null, val)
    return true
  }

  **
  ** Replace existing value only if current value matches expected oldVal.
  ** Returns true if replaced, false otherwise.
  **
  Bool replace(Str key, Obj? expectedOldVal, Obj? newVal)
  {
    store := getStore(key)
    curr := store.get(key)
    if (curr == null || curr.val != expectedOldVal) return false

    store.put(key, newVal, (curr.expireTime > 0) ? (curr.expireTime - DateTime.now.toJava).max(1) : 0)
    notifyListeners(MapEventType.entry_updated, key, expectedOldVal, newVal)
    return true
  }

  **
  ** Remove entry mapped to key. Returns removed value or null.
  **
  Obj? remove(Str key)
  {
    store := getStore(key)
    oldEntry := store.get(key)
    if (oldEntry == null) return null

    oldVal := oldEntry.val
    store.remove(key)
    notifyListeners(MapEventType.entry_removed, key, oldVal, null)
    return oldVal
  }

  **
  ** Check if key exists in map.
  **
  Bool containsKey(Str key)
  {
    return getStore(key).get(key) != null
  }

  **
  ** Execute atomic EntryProcessor directly on partition entry.
  **
  Obj? executeOnKey(Str key, EntryProcessor processor)
  {
    store := getStore(key)
    entry := store.get(key)
    if (entry == null)
    {
      // Create empty entry for processor initialization
      now := DateTime.now.toJava
      entry = CacheEntry(key, null, HybridLogicalClock(now, 0), 0)
      store.put(key, null)
    }

    oldVal := entry.val
    result := processor.process(entry)
    newVal := entry.val

    if (newVal != oldVal)
    {
      notifyListeners(MapEventType.entry_updated, key, oldVal, newVal)
    }
    return result
  }

  **
  ** Total number of live entries across all partitions.
  **
  Int size()
  {
    sum := 0
    partitions.vals.each |PartitionStore s| { sum += s.size }
    return sum
  }

  **
  ** Check if map contains zero entries.
  **
  Bool isEmpty() { return size == 0 }

  **
  ** Clear all entries across all partitions.
  **
  Void clear()
  {
    partitions.vals.each |PartitionStore s| { s.clear }
  }

  **
  ** Register a continuous mutation listener.
  **
  Void addListener(|MapEventType, Str, Obj?, Obj?| listener)
  {
    listeners.add(listener)
  }

  private Void notifyListeners(MapEventType evt, Str key, Obj? oldVal, Obj? newVal)
  {
    listeners.each |l|
    {
      l(evt, key, oldVal, newVal)
    }
  }
}
