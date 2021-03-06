**
** Unit tests for RingQueue circular buffer.
**
class RingQueueTest : Test
{
  Void testBoundedBackpressure()
  {
    q := RingQueue(4, false)
    verifyEq(q.capacity, 8) // Rounded up to power of two
    verifyEq(q.size, 0)
    verify(q.isEmpty)

    for (i := 0; i < 8; ++i)
    {
      verify(q.offer("item-$i"))
    }

    verify(q.isFull)
    verifyEq(q.size, 8)

    // Cannot offer when full
    verifyEq(q.offer("overflow"), false)

    // Poll items in FIFO order
    for (i := 0; i < 8; ++i)
    {
      verifyEq(q.poll, "item-$i")
    }

    verify(q.isEmpty)
    verifyEq(q.poll, null)
  }

  Void testOverwriteMode()
  {
    q := RingQueue(4, true) // cap = 8

    for (i := 0; i < 12; ++i)
    {
      q.offer(i)
    }

    verifyEq(q.size, 8)
    // Items 0..3 were overwritten; items 4..11 remain
    verifyEq(q.peek, 4)
    for (i := 4; i < 12; ++i)
    {
      verifyEq(q.poll, i)
    }
    verify(q.isEmpty)
  }
}
