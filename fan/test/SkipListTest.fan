**
** Unit tests for SkipList ordered index.
**
class SkipListTest : Test
{
  Void testOrderedInsertionAndIteration()
  {
    sl := SkipList()
    keys := ["delta", "alpha", "charlie", "bravo", "echo"]
    keys.each |k| { sl.put(k, "val-$k") }

    verifyEq(sl.size, 5)
    verifyEq(sl.firstKey, "alpha")
    verifyEq(sl.lastKey, "echo")

    sorted := Str[,]
    sl.each |_, k| { sorted.add(k) }
    verifyEq(sorted, ["alpha", "bravo", "charlie", "delta", "echo"])
  }

  Void testRangeQueries()
  {
    sl := SkipList()
    for (i := 0; i < 20; ++i)
    {
      k := (i < 10 ? "key-0$i" : "key-$i")
      sl.put(k, i)
    }

    range := sl.range("key-05", "key-12")
    verifyEq(range.size, 7) // 05, 06, 07, 08, 09, 10, 11
    verifyEq(range["key-05"], 5)
    verifyEq(range["key-11"], 11)
    verifyEq(range["key-12"], null)
  }

  Void testPrefixScan()
  {
    sl := SkipList()
    sl.put("user:100:profile", "A")
    sl.put("user:100:orders", "B")
    sl.put("user:101:profile", "C")
    sl.put("session:100", "D")

    scan100 := sl.prefixScan("user:100:")
    verifyEq(scan100.size, 2)
    verifyEq(scan100["user:100:profile"], "A")
    verifyEq(scan100["user:100:orders"], "B")

    scanAllUsers := sl.prefixScan("user:")
    verifyEq(scanAllUsers.size, 3)
  }

  Void testDeletionAndUpdates()
  {
    sl := SkipList()
    sl.put("k1", 10)
    sl.put("k2", 20)
    sl.put("k3", 30)

    // Overwrite
    old := sl.put("k2", 200)
    verifyEq(old, 20)
    verifyEq(sl.get("k2"), 200)

    // Remove
    rem := sl.remove("k2")
    verifyEq(rem, 200)
    verifyEq(sl.size, 2)
    verifyEq(sl.get("k2"), null)
    verifyEq(sl.get("k1"), 10)
    verifyEq(sl.get("k3"), 30)

    // Non-existent remove
    verifyEq(sl.remove("unknown"), null)
  }
}
