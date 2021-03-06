**
** RingQueue: Power-of-two circular ring buffer for high-throughput actor message passing.
**
** Features:
** - Bitwise masking index calculations (no expensive modulo).
** - Dual modes: backpressure (fail on full) or ring overwrite (ring buffer telemetry).
** - Lock-free single-producer single-consumer compatible layout.
**
class RingQueue
{
  private Obj?[] buffer
  private Int mask
  private Int head := 0
  private Int tail := 0
  private Bool allowOverwrite

  **
  ** Create ring queue with capacity rounded to next power of two.
  **
  new make(Int capacity := 1024, Bool allowOverwrite := false)
  {
    cap := Bits.nextPowerOfTwo(capacity.max(8))
    this.buffer = Obj?[,].fill(null, cap)
    this.mask = cap - 1
    this.allowOverwrite = allowOverwrite
  }

  **
  ** Number of items currently enqueued.
  **
  Int size() { tail - head }

  **
  ** Total allocated ring capacity.
  **
  Int capacity() { buffer.size }

  **
  ** Check if the queue is empty.
  **
  Bool isEmpty() { tail == head }

  **
  ** Check if the queue is at capacity.
  **
  Bool isFull() { size == buffer.size }

  **
  ** Enqueue an item. Returns true if enqueued, false if full (when overwrite is disabled).
  **
  Bool offer(Obj item)
  {
    if (isFull)
    {
      if (!allowOverwrite) return false
      // Overwrite oldest entry: advance head
      head++
    }
    buffer[tail.and(mask)] = item
    tail++
    return true
  }

  **
  ** Dequeue the oldest item, or null if empty.
  **
  Obj? poll()
  {
    if (isEmpty) return null
    idx := head.and(mask)
    item := buffer[idx]
    buffer[idx] = null
    head++
    return item
  }

  **
  ** Peek at the oldest item without removing it, or null if empty.
  **
  Obj? peek()
  {
    if (isEmpty) return null
    return buffer[head.and(mask)]
  }

  **
  ** Clear all enqueued items.
  **
  Void clear()
  {
    while (!isEmpty)
    {
      poll
    }
    head = 0
    tail = 0
  }
}
