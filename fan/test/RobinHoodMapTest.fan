**
** Unit tests for RobinHoodMap open-addressing hash table.
**
class RobinHoodMapTest : Test
{
  Void testBasicOperations()
  {
    map := RobinHoodMap(8)
    verifyEq(map.size, 0)
    verify(map.isEmpty)

    map.put("key1", "val1")
    map.put("key2", "val2")
    map.put("key3", "val3")

    verifyEq(map.size, 3)
    verifyEq(map.get("key1"), "val1")
    verifyEq(map.get("key2"), "val2")
    verifyEq(map.get("key3"), "val3")
    verifyEq(map.get("non-existent"), null)

    // Overwrite
    old := map.put("key2", "val2-updated")
    verifyEq(old, "val2")
    verifyEq(map.get("key2"), "val2-updated")
    verifyEq(map.size, 3)

    // Remove
    removed := map.remove("key2")
    verifyEq(removed, "val2-updated")
    verifyEq(map.size, 2)
    verifyEq(map.get("key2"), null)
    verifyEq(map.get("key1"), "val1")
    verifyEq(map.get("key3"), "val3")
  }

  Void testBackwardShiftDeletion()
  {
    map := RobinHoodMap(16)
    // Insert items designed to probe and cluster
    for (i := 0; i < 20; ++i)
    {
      map.put("clustered-item-$i", i * 10)
    }

    verifyEq(map.size, 20)

    // Remove middle items
    for (i := 5; i < 15; ++i)
    {
      verifyEq(map.remove("clustered-item-$i"), i * 10)
    }

    verifyEq(map.size, 10)

    // Ensure remaining items are still reachable
    for (i := 0; i < 5; ++i)
    {
      verifyEq(map.get("clustered-item-$i"), i * 10)
    }
    for (i := 15; i < 20; ++i)
    {
      verifyEq(map.get("clustered-item-$i"), i * 10)
    }
  }

  Void testDynamicResizing()
  {
    map := RobinHoodMap(8)
    n := 500

    for (i := 0; i < n; ++i)
    {
      map.put("dyn-$i", i)
    }

    verifyEq(map.size, n)
    verify(map.capacity >= n)
    verify(map.loadFactor <= 0.88f)

    for (i := 0; i < n; ++i)
    {
      verifyEq(map.get("dyn-$i"), i)
    }
  }

  Void testKeysAndValuesIteration()
  {
    map := RobinHoodMap(16)
    map.put("a", 1)
    map.put("b", 2)
    map.put("c", 3)

    keys := map.keysList.sort
    vals := map.valsList.sort

    verifyEq(keys, ["a", "b", "c"])
    verifyEq(vals.size, 3)
    verifyEq(vals[0], 1)
    verifyEq(vals[1], 2)
    verifyEq(vals[2], 3)

    map.clear
    verifyEq(map.size, 0)
    verify(map.isEmpty)
  }
}
