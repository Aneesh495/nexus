**
** Unit tests for NodeId and ClusterNode descriptors.
**
class ClusterNodeTest : Test
{
  Void testNodeIdParsingAndEquality()
  {
    n1 := NodeId("node-1", "10.0.0.1", 8000, 8080, "us-east-1a", 1000)
    verifyEq(n1.id, "node-1")
    verifyEq(n1.host, "10.0.0.1")
    verifyEq(n1.port, 8000)
    verifyEq(n1.httpPort, 8080)
    verifyEq(n1.zone, "us-east-1a")

    addrStr := n1.toAddressStr
    parsed := NodeId.fromAddressStr("node-1", addrStr)
    verifyEq(parsed, n1)

    n2 := NodeId("node-2", "10.0.0.2", 8000, 8080, "us-east-1b", 2000)
    verify(n1 != n2)
  }

  Void testClusterNodeLifecycle()
  {
    nid := NodeId("node-alpha")
    node := ClusterNode(nid, NodeStatus.joining)

    verifyEq(node.isActive, false)
    verifyEq(node.isAlive, false)

    node.status = NodeStatus.active
    verifyEq(node.isActive, true)
    verifyEq(node.isAlive, true)

    node.status = NodeStatus.suspect
    verifyEq(node.isActive, false)
    verifyEq(node.isAlive, true) // Suspect is still alive until confirmed dead

    node.status = NodeStatus.dead
    verifyEq(node.isAlive, false)

    // Incarnation refutation
    verifyEq(node.incarnation, 0)
    node.advanceIncarnation
    verifyEq(node.incarnation, 1)

    // Heartbeat update
    node.updateHeartbeat(5000)
    verifyEq(node.lastHeartbeatTime, 5000)
  }
}
