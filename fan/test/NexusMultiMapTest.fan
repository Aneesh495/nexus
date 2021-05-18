**
** Unit tests for NexusMultiMap and ContinuousQuery event filtering.
**
class NexusMultiMapTest : Test
{
  Void testMultiValueAccumulationAndRemoval()
  {
    mm := NexusMultiMap("orders-by-customer")
    verifyEq(mm.multiMapName, "orders-by-customer")
    verifyEq(mm.totalSize, 0)
    verifyEq(mm.keyCount, 0)

    mm.put("cust:101", "order:A1")
    mm.put("cust:101", "order:A2")
    mm.put("cust:101", "order:A3")
    mm.put("cust:102", "order:B1")

    verifyEq(mm.keyCount, 2)
    verifyEq(mm.totalSize, 4)
    verifyEq(mm.valueCount("cust:101"), 3)
    verifyEq(mm.valueCount("cust:102"), 1)

    vals := mm.get("cust:101")
    verifyEq(vals.size, 3)
    verifyEq(vals[0], "order:A1")
    verifyEq(vals[2], "order:A3")

    verifyTrue(mm.containsEntry("cust:101", "order:A2"))
    verifyFalse(mm.containsEntry("cust:101", "order:nonexistent"))

    // Remove single value
    removedVal := mm.removeValue("cust:101", "order:A2")
    verifyTrue(removedVal)
    verifyEq(mm.valueCount("cust:101"), 2)
    verifyFalse(mm.containsEntry("cust:101", "order:A2"))

    // Remove all for key
    removedAll := mm.removeAll("cust:101")
    verifyEq(removedAll.size, 2)
    verifyEq(mm.keyCount, 1)
    verifyEq(mm.totalSize, 1)

    mm.clear
    verifyEq(mm.totalSize, 0)
    verifyEq(mm.keyCount, 0)
  }

  Void testContinuousQueryPrefixFiltering()
  {
    mm := NexusMultiMap("audit-stream")
    eventsReceived := Str[,]

    // Listen only to audit events with prefix "audit:security:"
    pred := PrefixPredicate("audit:security:")
    query := ContinuousQuery(pred) |MapEventType evt, Str key, Obj? val|
    {
      eventsReceived.add("${evt.name}:${key}:${val}")
    }
    mm.addContinuousQuery(query)

    // Put non-matching key
    mm.put("audit:metrics:cpu", "90%")
    verifyEq(eventsReceived.size, 0)

    // Put matching keys
    mm.put("audit:security:login", "success")
    mm.put("audit:security:logout", "user:5")

    verifyEq(eventsReceived.size, 2)
    verifyEq(eventsReceived[0], "entry_added:audit:security:login:success")
    verifyEq(eventsReceived[1], "entry_added:audit:security:logout:user:5")

    // Remove matching key
    mm.removeValue("audit:security:login", "success")
    verifyEq(eventsReceived.size, 3)
    verifyEq(eventsReceived[2], "entry_removed:audit:security:login:success")
  }

  Void testExactMatchPredicate()
  {
    pred := ExactMatchPredicate("topic:alerts", "CRITICAL")
    verifyTrue(pred.matches("topic:alerts", "CRITICAL"))
    verifyFalse(pred.matches("topic:alerts", "INFO"))
    verifyFalse(pred.matches("topic:other", "CRITICAL"))
  }
}
