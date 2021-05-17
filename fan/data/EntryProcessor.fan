**
** EntryProcessor: Mixin for executing atomic in-place mutations on a cache entry
** directly within the partition thread without full network deserialization roundtrips.
**
** Reference:
** JCache (JSR-107) javax.cache.processor.EntryProcessor,
** Hazelcast In-Memory Data Grid EntryProcessor pattern.
**
mixin EntryProcessor
{
  **
  ** Process and mutate the specified entry in-place.
  ** Returns an arbitrary computational result passed back to caller.
  **
  abstract Obj? process(CacheEntry entry)
}
