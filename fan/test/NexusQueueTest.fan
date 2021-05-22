**
** Unit tests for NexusQueue bounded FIFO and visibility lease semantics.
**
class NexusQueueTest : Test
{
  Void testBoundedFifoOrderingAndCapacity()
  {
    q := NexusQueue("work-queue", 3)
    verifyEq(q.queueName, "work-queue")
    verifyEq(q.readySize, 0)
    verifyEq(q.remainingCapacity, 3)

    verifyTrue(q.offer("job-1"))
    verifyTrue(q.offer("job-2"))
    verifyTrue(q.offer("job-3"))
    // Queue full (capacity 3)
    verifyFalse(q.offer("job-4"))
    verifyEq(q.readySize, 3)
    verifyEq(q.remainingCapacity, 0)

    verifyEq(q.peek, "job-1")
    verifyEq(q.poll, "job-1")
    verifyEq(q.poll, "job-2")
    verifyEq(q.poll, "job-3")
    verifyNull(q.poll)
  }

  Void testLeaseAckLifecycle()
  {
    q := NexusQueue("lease-queue", 10)
    q.offer("msg-A")
    q.offer("msg-B")

    t0 := 10_000
    // Check out msg-A with 5000ms lease
    leaseA := q.lease(5000, t0)
    verifyNotNull(leaseA)
    verifyEq(leaseA.item, "msg-A")
    verifyEq(q.readySize, 1) // only msg-B is ready
    verifyEq(q.leasedCount, 1)

    // Ack msg-A
    acked := q.ack(leaseA.leaseToken)
    verifyTrue(acked)
    verifyEq(q.leasedCount, 0)
    verifyEq(q.readySize, 1)

    // msg-B remains
    verifyEq(q.poll, "msg-B")
  }

  Void testLeaseNackRequeue()
  {
    q := NexusQueue("nack-queue", 10, 3)
    q.offer("task-1")

    lease := q.lease(5000, 1000)
    verifyNotNull(lease)
    verifyEq(q.readySize, 0)

    // Nack releases back to queue
    nacked := q.nack(lease.leaseToken)
    verifyTrue(nacked)
    verifyEq(q.readySize, 1)
    verifyEq(q.leasedCount, 0)

    verifyEq(q.poll, "task-1")
  }

  Void testVisibilityTimeoutExpiration()
  {
    q := NexusQueue("timeout-queue", 10, 3)
    q.offer("payload-1")

    t0 := 10_000
    lease := q.lease(2000, t0) // expires at t0 + 2000
    verifyNotNull(lease)
    verifyEq(q.readySize, 0)
    verifyEq(q.leasedCount, 1)

    // Before expiry (t0 + 1000ms)
    requeued0 := q.sweepExpiredLeases(t0 + 1000)
    verifyEq(requeued0, 0)
    verifyEq(q.readySize, 0)

    // After expiry (t0 + 2500ms)
    requeued1 := q.sweepExpiredLeases(t0 + 2500)
    verifyEq(requeued1, 1)
    verifyEq(q.readySize, 1)
    verifyEq(q.leasedCount, 0)

    verifyEq(q.poll, "payload-1")
  }

  Void testDrainTo()
  {
    q := NexusQueue("drain-queue", 10)
    q.offer("a")
    q.offer("b")
    q.offer("c")

    target := Obj?[,]
    drained := q.drainTo(target, 2)
    verifyEq(drained, 2)
    verifyEq(target.size, 2)
    verifyEq(target[0], "a")
    verifyEq(target[1], "b")
    verifyEq(q.readySize, 1)
  }
}
