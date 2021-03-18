**
** EvictionPolicy: Contract for cache eviction algorithms.
**
** Monitors access patterns and selects victim entries when capacity limits are reached.
**
mixin EvictionPolicy
{
  **
  ** Notify policy that an existing entry was accessed.
  **
  abstract Void recordAccess(CacheEntry entry)

  **
  ** Notify policy that a new entry was inserted.
  **
  abstract Void recordInsert(CacheEntry entry)

  **
  ** Notify policy that an entry was removed from cache.
  **
  abstract Void recordRemove(CacheEntry entry)

  **
  ** Select and return key of victim entry to evict, or null if policy is empty.
  **
  abstract Str? evictNext()

  **
  ** Number of tracked entries.
  **
  abstract Int size()

  **
  ** Clear all tracking state.
  **
  abstract Void clear()
}
