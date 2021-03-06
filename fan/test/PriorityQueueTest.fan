**
** Unit tests for PriorityQueue binary min-heap.
**
class PriorityQueueTest : Test
{
  Void testOrdering()
  {
    pq := PriorityQueue()
    verify(pq.isEmpty)
    verifyEq(pq.size, 0)

    pq.push(50, "fifty")
    pq.push(10, "ten")
    pq.push(30, "thirty")
    pq.push(5,  "five")
    pq.push(20, "twenty")

    verifyEq(pq.size, 5)
    verifyEq(pq.peek, "five")
    verifyEq(pq.peekPriority, 5)

    verifyEq(pq.pop, "five")
    verifyEq(pq.pop, "ten")
    verifyEq(pq.pop, "twenty")
    verifyEq(pq.pop, "thirty")
    verifyEq(pq.pop, "fifty")
    verify(pq.isEmpty)
    verifyEq(pq.pop, null)
  }

  Void testDuplicatePriorities()
  {
    pq := PriorityQueue()
    pq.push(10, "a")
    pq.push(10, "b")
    pq.push(10, "c")

    verifyEq(pq.size, 3)
    popped := [pq.pop, pq.pop, pq.pop]
    verifyEq(popped.size, 3)
    verify(popped.contains("a"))
    verify(popped.contains("b"))
    verify(popped.contains("c"))
  }
}
