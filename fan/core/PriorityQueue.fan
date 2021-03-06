**
** PriorityQueue: Binary min-heap with entry priorities and fast decrease-key tracking.
**
** Used for timer expiration sweeps, scheduled task queues, and priority job scheduling.
**
class PriorityQueue
{
  private HeapNode[] heap := HeapNode[,]

  **
  ** Create empty priority queue.
  **
  new make(Int initialCapacity := 32)
  {
    heap.capacity = initialCapacity
  }

  **
  ** Number of elements in the priority queue.
  **
  Int size() { heap.size }

  **
  ** Check if empty.
  **
  Bool isEmpty() { heap.isEmpty }

  **
  ** Add item with associated numeric priority (lowest priority value is popped first).
  **
  Void push(Int priority, Obj item)
  {
    node := HeapNode(priority, item)
    heap.add(node)
    siftUp(heap.size - 1)
  }

  **
  ** Peek at highest-priority item (lowest numeric priority value), or null if empty.
  **
  Obj? peek()
  {
    if (heap.isEmpty) return null
    return heap[0].item
  }

  **
  ** Peek at highest priority value, or null if empty.
  **
  Int? peekPriority()
  {
    if (heap.isEmpty) return null
    return heap[0].priority
  }

  **
  ** Remove and return the highest-priority item, or null if empty.
  **
  Obj? pop()
  {
    if (heap.isEmpty) return null
    top := heap[0].item
    last := heap.pop

    if (!heap.isEmpty)
    {
      heap[0] = last
      siftDown(0)
    }

    return top
  }

  **
  ** Clear all entries.
  **
  Void clear()
  {
    heap.clear
  }

  private Void siftUp(Int index)
  {
    k := index
    while (k > 0)
    {
      parent := (k - 1).shiftr(1)
      if (heap[k].priority < heap[parent].priority)
      {
        swap(k, parent)
        k = parent
      }
      else
      {
        break
      }
    }
  }

  private Void siftDown(Int index)
  {
    k := index
    half := heap.size.shiftr(1)
    while (k < half)
    {
      left := k.shiftl(1) + 1
      right := left + 1
      smallest := left

      if (right < heap.size && heap[right].priority < heap[left].priority)
      {
        smallest = right
      }

      if (heap[smallest].priority < heap[k].priority)
      {
        swap(k, smallest)
        k = smallest
      }
      else
      {
        break
      }
    }
  }

  private Void swap(Int i, Int j)
  {
    tmp := heap[i]
    heap[i] = heap[j]
    heap[j] = tmp
  }
}

internal class HeapNode
{
  Int priority
  Obj item

  new make(Int priority, Obj item)
  {
    this.priority = priority
    this.item = item
  }
}
