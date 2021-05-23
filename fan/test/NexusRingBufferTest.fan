**
** Unit tests for NexusRingBuffer sequence tracking and overwrite semantics.
**
class NexusRingBufferTest : Test
{
  Void testSequentialAppendAndReads()
  {
    ring := NexusRingBuffer("events", 16)
    verifyEq(ring.bufferName, "events")
    verifyEq(ring.ringCapacity, 16)
    verifyEq(ring.size, 0)
    verifyTrue(ring.isEmpty)

    s0 := ring.add("event-0")
    s1 := ring.add("event-1")
    s2 := ring.add("event-2")

    verifyEq(s0, 0)
    verifyEq(s1, 1)
    verifyEq(s2, 2)
    verifyEq(ring.size, 3)
    verifyEq(ring.headSeq, 0)
    verifyEq(ring.tailSeq, 2)

    verifyEq(ring.readOne(0), "event-0")
    verifyEq(ring.readOne(1), "event-1")
    verifyEq(ring.readOne(2), "event-2")
    verifyNull(ring.readOne(3)) // future sequence

    // Batch read
    batch := ring.readMany(0, 2)
    verifyEq(batch.size, 2)
    verifyEq(batch[0], "event-0")
    verifyEq(batch[1], "event-1")

    batchAll := ring.readMany(1, 10)
    verifyEq(batchAll.size, 2)
    verifyEq(batchAll[0], "event-1")
    verifyEq(batchAll[1], "event-2")
  }

  Void testOverwriteAndStaleSequence()
  {
    ring := NexusRingBuffer("overwriting-ring", 8, RingBufferOverflowPolicy.overwrite)
    verifyEq(ring.ringCapacity, 8)

    // Append 8 items: sequences 0..7
    8.times |i|
    {
      ring.add("item-${i}")
    }
    verifyEq(ring.size, 8)
    verifyTrue(ring.isFull)
    verifyEq(ring.headSeq, 0)
    verifyEq(ring.tailSeq, 7)

    // Append 4 more items: sequences 8..11 -> head must advance to 4
    4.times |i|
    {
      ring.add("item-${8 + i}")
    }
    verifyEq(ring.size, 8)
    verifyEq(ring.headSeq, 4)
    verifyEq(ring.tailSeq, 11)

    // Reading overwritten sequence 0..3 must throw StaleSequenceErr
    verifyErr(StaleSequenceErr#) { ring.readOne(0) }
    verifyErr(StaleSequenceErr#) { ring.readOne(3) }

    // Reading available sequence 4..11 succeeds
    verifyEq(ring.readOne(4), "item-4")
    verifyEq(ring.readOne(11), "item-11")

    // Batch reading from stale sequence throws
    verifyErr(StaleSequenceErr#) { ring.readMany(2, 5) }
  }

  Void testRejectPolicy()
  {
    ring := NexusRingBuffer("reject-ring", 8, RingBufferOverflowPolicy.reject)

    8.times |i|
    {
      seq := ring.add("v-$i")
      verifyTrue(seq >= 0)
    }

    verifyTrue(ring.isFull)

    // Next add must be rejected with -1
    rej := ring.add("overflow-item")
    verifyEq(rej, -1)
    verifyEq(ring.size, 8)
    verifyEq(ring.tailSeq, 7)
    verifyEq(ring.readOne(0), "v-0")
  }
}
