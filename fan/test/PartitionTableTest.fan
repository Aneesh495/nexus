**
** Unit tests for PartitionTable and PartitionDiff routing.
**
class PartitionTableTest : Test
{
  Void testBuildFromRing()
  {
    ring := HashRing(64)
    n1 := NodeId("node-A")
    n2 := NodeId("node-B")
    ring.addNode(n1)
    ring.addNode(n2)

    table := PartitionTable.buildFromRing(ring, 128, 2, 1)

    verifyEq(table.epoch, 1)
    verifyEq(table.partitionCount, 128)
    verifyEq(table.replicaFactor, 2)

    // Verify all 128 partitions are mapped
    for (p := 0; p < 128; ++p)
    {
      assign := table.getAssignment(p)
      verify(assign != null)
      verify(assign.primary == n1 || assign.primary == n2)
      verifyEq(assign.replicas.size, 1) // 1 backup replica
    }

    // Key routing
    primary := table.getPrimary("customer:999")
    verify(primary != null)
    allReps := table.getAllReplicas("customer:999")
    verifyEq(allReps.size, 2)
  }

  Void testDiffBetweenEpochs()
  {
    ring := HashRing(64)
    ring.addNode(NodeId("node-A"))
    ring.addNode(NodeId("node-B"))

    t1 := PartitionTable.buildFromRing(ring, 64, 2, 1)

    // Add node-C and build epoch 2
    ring.addNode(NodeId("node-C"))
    t2 := PartitionTable.buildFromRing(ring, 64, 2, 2)

    diff := t1.diff(t2)
    verifyEq(diff.oldEpoch, 1)
    verifyEq(diff.newEpoch, 2)
    verify(diff.movedPartitions.size > 0)

    // All moved partitions in t2 must now belong to node-C
    diff.movedPartitions.each |partId|
    {
      newOwner := diff.newOwners[partId]
      verifyEq(newOwner.id, "node-C")
    }
  }
}
