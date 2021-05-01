using concurrent

**
** Unit tests for ClusterTopologyActor concurrency and state transitions.
**
class ClusterTopologyActorTest : Test
{
  Void testJoinAndRouteLifecycle()
  {
    pool := ActorPool()
    localNode := NodeId("node-A:8000")
    cluster := ClusterTopologyActor(pool, localNode, 32, 2, 64)

    snap0 := cluster.getSnapshot
    verifyEq(snap0.epoch, 0)
    verifyEq(snap0.nodes.size, 1)

    // Join second node
    n2 := NodeId("node-B:8001")
    joined := cluster.join(n2)
    verifyTrue(joined)

    snap1 := cluster.getSnapshot
    verifyEq(snap1.epoch, 1)
    verifyEq(snap1.nodes.size, 2)

    // Join third node
    n3 := NodeId("node-C:8002")
    cluster.join(n3)

    snap2 := cluster.getSnapshot
    verifyEq(snap2.epoch, 2)
    verifyEq(snap2.nodes.size, 3)

    // Verify key routing
    route1 := cluster.queryRoute("user:1001")
    verifyNotNull(route1)
    verifyNotNull(route1.primary)
    verifyTrue(route1.primary == localNode || route1.primary == n2 || route1.primary == n3)

    // Leave a node
    left := cluster.leave(n2)
    verifyTrue(left)

    snap3 := cluster.getSnapshot
    verifyEq(snap3.epoch, 3)
    verifyEq(snap3.nodes.size, 2)

    pool.stop
    pool.join
  }

  Void testFailureDetectionAndEjection()
  {
    pool := ActorPool()
    localNode := NodeId("node-A:8000")
    cluster := ClusterTopologyActor(pool, localNode, 16, 2, 32)

    n2 := NodeId("node-B:8001")
    cluster.join(n2)

    t0 := 1000
    // Send 10 heartbeats
    10.times |i|
    {
      cluster.heartbeat(n2, t0 + i * 100)
    }

    // Tick at normal interval -> node-B remains online
    deadCount0 := cluster.tick(t0 + 1050)
    verifyEq(deadCount0, 0)
    verifyEq(cluster.getSnapshot.nodes.size, 2)

    // Tick after large silence -> node-B flagged as dead and ejected
    deadCount1 := cluster.tick(t0 + 20_000)
    verifyEq(deadCount1, 1)
    verifyEq(cluster.getSnapshot.nodes.size, 1)
    verifyEq(cluster.getSnapshot.epoch, 2)

    pool.stop
    pool.join
  }
}
