**
** Unit tests for NexusMap distributed key-value storage and EntryProcessor.
**
class NexusMapTest : Test
{
  Void testBasicCrudOperations()
  {
    map := NexusMap("test-map", 8)
    verifyEq(map.mapName, "test-map")
    verifyEq(map.size, 0)
    verifyTrue(map.isEmpty)

    // Put entries
    map.put("user:101", "Alice")
    map.put("user:102", "Bob")
    map.put("user:103", "Charlie")

    verifyEq(map.size, 3)
    verifyFalse(map.isEmpty)
    verifyTrue(map.containsKey("user:101"))
    verifyEq(map.get("user:101"), "Alice")
    verifyEq(map.get("user:102"), "Bob")
    verifyNull(map.get("user:999"))

    // Overwrite
    oldVal := map.put("user:101", "Alicia")
    verifyEq(oldVal, "Alice")
    verifyEq(map.get("user:101"), "Alicia")

    // Remove
    removed := map.remove("user:102")
    verifyEq(removed, "Bob")
    verifyEq(map.size, 2)
    verifyFalse(map.containsKey("user:102"))

    map.clear
    verifyEq(map.size, 0)
    verifyTrue(map.isEmpty)
  }

  Void testConditionalPutAndReplace()
  {
    map := NexusMap("cond-map", 4)

    // putIfAbsent
    v1 := map.putIfAbsent("k1", "v1")
    verifyTrue(v1)
    verifyEq(map.get("k1"), "v1")

    v2 := map.putIfAbsent("k1", "v2-ignored")
    verifyFalse(v2)
    verifyEq(map.get("k1"), "v1")

    // replace
    r1 := map.replace("k1", "wrong-old", "v3")
    verifyFalse(r1)
    verifyEq(map.get("k1"), "v1")

    r2 := map.replace("k1", "v1", "v3-success")
    verifyTrue(r2)
    verifyEq(map.get("k1"), "v3-success")
  }

  Void testContinuousListeners()
  {
    map := NexusMap("events-map", 4)
    events := Str[,]

    map.addListener |MapEventType evt, Str key, Obj? oldVal, Obj? newVal|
    {
      events.add("${evt.name}:${key}:${oldVal}->${newVal}")
    }

    map.put("k1", "first")
    map.put("k1", "second")
    map.remove("k1")

    verifyEq(events.size, 3)
    verifyEq(events[0], "entry_added:k1:null->first")
    verifyEq(events[1], "entry_updated:k1:first->second")
    verifyEq(events[2], "entry_removed:k1:second->null")
  }

  Void testEntryProcessorAtomicMutation()
  {
    map := NexusMap("proc-map", 4)
    map.put("counter:clicks", 10)

    incrementProc := IncrementProcessor(5)
    res := map.executeOnKey("counter:clicks", incrementProc)

    verifyEq(res, 15)
    verifyEq(map.get("counter:clicks"), 15)
  }
}

internal class IncrementProcessor : EntryProcessor
{
  Int delta

  new make(Int delta)
  {
    this.delta = delta
  }

  override Obj? process(CacheEntry entry)
  {
    curr := entry.val as Int ?: 0
    updated := curr + delta
    entry.val = updated
    return updated
  }
}
