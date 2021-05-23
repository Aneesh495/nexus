**
** RingBufferOverflowPolicy: Action taken when appending to a full ring buffer.
**
enum class RingBufferOverflowPolicy
{
  overwrite,
  reject
}

**
** StaleSequenceErr: Thrown when requested sequence has already been overwritten.
**
const class StaleSequenceErr : Err
{
  new make(Str msg := "") : super(msg) {}
}

**
** NexusRingBuffer: Circular streaming event buffer indexed by monotonic sequence numbers,
** modeled on the LMAX Disruptor ring buffer architecture.
**
** Reference:
** Thompson, Farah, Barker, Gee, Stewart, "Disruptor: High Performance Alternative to Bounded Queues",
** LMAX Whitepaper 2011.
**
class NexusRingBuffer
{
  private Str name
  private Int capacity
  private RingBufferOverflowPolicy overflowPolicy
  private Obj?[] buffer
  private Int mask
  private Int headSequence := 0
  private Int tailSequence := -1

  new make(Str name, Int capacity := 1024, RingBufferOverflowPolicy overflowPolicy := RingBufferOverflowPolicy.overwrite)
  {
    this.name           = name
    cap := Bits.nextPowerOfTwo(capacity.max(8))
    this.capacity       = cap
    this.overflowPolicy = overflowPolicy
    this.buffer         = Obj?[,].fill(null, cap)
    this.mask           = cap - 1
  }

  **
  ** Ring buffer identifier name.
  **
  Str bufferName() { return name }

  **
  ** Monotonic sequence number of the oldest retained item.
  **
  Int headSeq() { return headSequence }

  **
  ** Monotonic sequence number of the newest appended item. Returns -1 if empty.
  **
  Int tailSeq() { return tailSequence }

  **
  ** Total configured power-of-two slot capacity.
  **
  Int ringCapacity() { return capacity }

  **
  ** Current number of available items.
  **
  Int size()
  {
    if (tailSequence < headSequence) return 0
    return tailSequence - headSequence + 1
  }

  **
  ** Check if buffer is empty.
  **
  Bool isEmpty() { return size == 0 }

  **
  ** Check if buffer is at full capacity.
  **
  Bool isFull() { return size >= capacity }

  **
  ** Append an item to the ring buffer.
  ** Returns assigned sequence number, or -1 if full and policy is reject.
  **
  Int add(Obj? item)
  {
    if (isFull)
    {
      if (overflowPolicy == RingBufferOverflowPolicy.reject)
      {
        return -1
      }
      // Overwrite: advance headSequence to drop oldest entry
      headSequence++
    }

    tailSequence++
    slot := tailSequence.and(mask)
    buffer[slot] = item
    return tailSequence
  }

  **
  ** Read item at specific monotonic sequence number.
  ** Throws StaleSequenceErr if sequence has already been overwritten.
  ** Returns null if sequence has not yet been written.
  **
  Obj? readOne(Int sequence)
  {
    if (sequence < headSequence)
    {
      throw StaleSequenceErr("Sequence $sequence has been overwritten (head is $headSequence)")
    }
    if (sequence > tailSequence)
    {
      return null
    }

    slot := sequence.and(mask)
    return buffer[slot]
  }

  **
  ** Batch read items starting from startSequence up to maxCount.
  **
  Obj?[] readMany(Int startSequence, Int maxCount := 100)
  {
    if (startSequence < headSequence)
    {
      throw StaleSequenceErr("Start sequence $startSequence has been overwritten (head is $headSequence)")
    }
    if (startSequence > tailSequence || maxCount <= 0)
    {
      return Obj?[,]
    }

    available := (tailSequence - startSequence + 1).min(maxCount)
    result := Obj?[,]
    available.times |i|
    {
      seq := startSequence + i
      slot := seq.and(mask)
      result.add(buffer[slot])
    }
    return result
  }

  **
  ** Clear buffer and reset sequence pointers.
  **
  Void clear()
  {
    buffer.fill(null, capacity)
    headSequence = 0
    tailSequence = -1
  }
}
