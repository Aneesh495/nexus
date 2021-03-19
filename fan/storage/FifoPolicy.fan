**
** FifoPolicy: First-In First-Out cache eviction policy.
**
** Evicts entries strictly in the order they were inserted, ignoring subsequent accesses.
**
class FifoPolicy : EvictionPolicy
{
  private Str[] queue := Str[,]
  private Str:Bool existsMap := Str:Bool[:]

  override Void recordAccess(CacheEntry entry)
  {
    // FIFO ignores subsequent access hits
    if (!existsMap.containsKey(entry.key))
    {
      recordInsert(entry)
    }
  }

  override Void recordInsert(CacheEntry entry)
  {
    if (existsMap.containsKey(entry.key)) return
    queue.add(entry.key)
    existsMap[entry.key] = true
  }

  override Void recordRemove(CacheEntry entry)
  {
    if (existsMap.remove(entry.key) != null)
    {
      idx := queue.index(entry.key)
      if (idx != null)
      {
        queue.removeAt(idx)
      }
    }
  }

  override Str? evictNext()
  {
    while (!queue.isEmpty)
    {
      candidate := queue.removeAt(0)
      if (existsMap.remove(candidate) != null)
      {
        return candidate
      }
    }
    return null
  }

  override Int size() { existsMap.size }

  override Void clear()
  {
    queue.clear
    existsMap.clear
  }
}
