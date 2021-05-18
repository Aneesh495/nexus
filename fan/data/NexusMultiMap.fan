**
** NexusMultiMap: Distributed multi-value map associating individual keys
** with ordered collections of values, integrated with ContinuousQuery subscriptions.
**
class NexusMultiMap
{
  private Str name
  private Str:Obj?[] store := Str:Obj?[:]
  private ContinuousQuery[] queries := ContinuousQuery[,]

  new make(Str name)
  {
    this.name = name
  }

  **
  ** MultiMap identifier name.
  **
  Str multiMapName() { return name }

  **
  ** Append a value under key. Multiple calls with same key accumulate values.
  **
  Void put(Str key, Obj? val)
  {
    list := store[key]
    if (list == null)
    {
      list = Obj?[,]
      store[key] = list
    }
    list.add(val)
    dispatchContinuousQueries(MapEventType.entry_added, key, val)
  }

  **
  ** Get all values associated with key. Returns immutable copy or empty list.
  **
  Obj?[] get(Str key)
  {
    list := store[key]
    if (list == null) return Obj?[,]
    return list.dup.toImmutable
  }

  **
  ** Remove a single specific value associated with key.
  ** Returns true if the value was found and removed.
  **
  Bool removeValue(Str key, Obj? val)
  {
    list := store[key]
    if (list == null) return false

    idx := list.index(val)
    if (idx != null)
    {
      list.removeAt(idx)
      if (list.isEmpty) store.remove(key)
      dispatchContinuousQueries(MapEventType.entry_removed, key, val)
      return true
    }
    return false
  }

  **
  ** Remove all values associated with key. Returns removed values list.
  **
  Obj?[] removeAll(Str key)
  {
    list := store.remove(key)
    if (list == null) return Obj?[,]
    list.each |v|
    {
      dispatchContinuousQueries(MapEventType.entry_removed, key, v)
    }
    return list.toImmutable
  }

  **
  ** Number of values mapped to a specific key.
  **
  Int valueCount(Str key)
  {
    list := store[key]
    return list != null ? list.size : 0
  }

  **
  ** Total count of distinct keys.
  **
  Int keyCount() { return store.size }

  **
  ** Total count of all key-value pairings across the multimap.
  **
  Int totalSize()
  {
    sum := 0
    store.vals.each |Obj?[] list| { sum += list.size }
    return sum
  }

  **
  ** Check if key is present.
  **
  Bool containsKey(Str key)
  {
    return store.containsKey(key)
  }

  **
  ** Check if exact key-value association exists.
  **
  Bool containsEntry(Str key, Obj? val)
  {
    list := store[key]
    if (list == null) return false
    return list.contains(val)
  }

  **
  ** Clear all entries.
  **
  Void clear()
  {
    store.clear
  }

  **
  ** Register a continuous query subscription.
  **
  Void addContinuousQuery(ContinuousQuery query)
  {
    queries.add(query)
  }

  private Void dispatchContinuousQueries(MapEventType evt, Str key, Obj? val)
  {
    queries.each |q|
    {
      q.publishEvent(evt, key, val)
    }
  }
}
