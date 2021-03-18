**
** LfuPolicy: O(1) Least Frequently Used cache eviction policy using frequency buckets.
**
** Reference:
** Arun et al., "An O(1) algorithm for implementing the LFU cache eviction scheme", 2010.
**
class LfuPolicy : EvictionPolicy
{
  private Str:LfuNode nodeMap := Str:LfuNode[:]
  private Int:Str:LfuNode freqBuckets := Int:Str:LfuNode[:]
  private Int minFreq := 0

  override Void recordAccess(CacheEntry entry)
  {
    node := nodeMap[entry.key]
    if (node != null)
    {
      oldFreq := node.freq
      newFreq := oldFreq + 1
      node.freq = newFreq

      // Remove from old frequency bucket
      oldBucket := freqBuckets[oldFreq]
      if (oldBucket != null)
      {
        oldBucket.remove(entry.key)
        if (oldBucket.isEmpty)
        {
          freqBuckets.remove(oldFreq)
          if (minFreq == oldFreq)
          {
            minFreq = newFreq
          }
        }
      }

      // Add to new frequency bucket
      newBucket := freqBuckets[newFreq]
      if (newBucket == null)
      {
        newBucket = Str:LfuNode[:]
        freqBuckets[newFreq] = newBucket
      }
      newBucket[entry.key] = node
    }
    else
    {
      recordInsert(entry)
    }
  }

  override Void recordInsert(CacheEntry entry)
  {
    existing := nodeMap[entry.key]
    if (existing != null)
    {
      recordAccess(entry)
      return
    }

    newNode := LfuNode(entry.key, 1)
    nodeMap[entry.key] = newNode

    bucket1 := freqBuckets[1]
    if (bucket1 == null)
    {
      bucket1 = Str:LfuNode[:]
      freqBuckets[1] = bucket1
    }
    bucket1[entry.key] = newNode
    minFreq = 1
  }

  override Void recordRemove(CacheEntry entry)
  {
    node := nodeMap.remove(entry.key)
    if (node != null)
    {
      bucket := freqBuckets[node.freq]
      if (bucket != null)
      {
        bucket.remove(entry.key)
        if (bucket.isEmpty)
        {
          freqBuckets.remove(node.freq)
        }
      }
    }
  }

  override Str? evictNext()
  {
    if (nodeMap.isEmpty) return null

    bucket := freqBuckets[minFreq]
    while (bucket == null || bucket.isEmpty)
    {
      freqBuckets.remove(minFreq)
      minFreq++
      bucket = freqBuckets[minFreq]
      if (minFreq > 100_000) break
    }

    if (bucket == null || bucket.isEmpty) return null

    victimKey := bucket.keys.first
    bucket.remove(victimKey)
    nodeMap.remove(victimKey)

    if (bucket.isEmpty)
    {
      freqBuckets.remove(minFreq)
    }

    return victimKey
  }

  override Int size() { nodeMap.size }

  override Void clear()
  {
    nodeMap.clear
    freqBuckets.clear
    minFreq = 0
  }
}

internal class LfuNode
{
  Str key
  Int freq

  new make(Str key, Int freq := 1)
  {
    this.key = key
    this.freq = freq
  }
}
