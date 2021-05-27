**
** Unit tests for NexusAtomicLong and NexusAtomicReference CAS primitives.
**
class NexusAtomicTest : Test
{
  Void testAtomicLongArithmeticAndCas()
  {
    counter := NexusAtomicLong("global-tx-id", 100)
    verifyEq(counter.atomicName, "global-tx-id")
    verifyEq(counter.get, 100)
    verifyEq(counter.currentVersion, 0)

    // Arithmetic
    verifyEq(counter.addAndGet(10), 110)
    verifyEq(counter.getAndAdd(5), 110)
    verifyEq(counter.get, 115)
    verifyEq(counter.incrementAndGet, 116)
    verifyEq(counter.decrementAndGet, 115)

    // Set and getAndSet
    verifyEq(counter.getAndSet(200), 115)
    verifyEq(counter.get, 200)

    // Compare and set
    // Mismatched expected value -> failure
    verifyFalse(counter.compareAndSet(999, 300))
    verifyEq(counter.get, 200)

    // Matching expected value -> success
    verifyTrue(counter.compareAndSet(200, 300))
    verifyEq(counter.get, 300)
    verifyTrue(counter.currentVersion > 5)
  }

  Void testAtomicReferenceCas()
  {
    ref := NexusAtomicReference("active-config", "config-v1")
    verifyEq(ref.referenceName, "active-config")
    verifyEq(ref.get, "config-v1")
    verifyEq(ref.currentVersion, 0)

    // getAndSet
    oldRef := ref.getAndSet("config-v2")
    verifyEq(oldRef, "config-v1")
    verifyEq(ref.get, "config-v2")

    // CAS failure
    verifyFalse(ref.compareAndSet("wrong-v", "config-v3"))
    verifyEq(ref.get, "config-v2")

    // CAS success
    verifyTrue(ref.compareAndSet("config-v2", "config-v3"))
    verifyEq(ref.get, "config-v3")

    // Null references
    verifyTrue(ref.compareAndSet("config-v3", null))
    verifyNull(ref.get)
    verifyTrue(ref.compareAndSet(null, "restored"))
    verifyEq(ref.get, "restored")
  }
}
