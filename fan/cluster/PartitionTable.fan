**
** PartitionAssignment: Holds primary and replica node assignments for a single partition.
**
const class PartitionAssignment
{
  const Int partitionId
  const NodeId primary
  const NodeId[] replicas

  new make(Int partitionId, NodeId primary, NodeId[] replicas)
  {
    this.partitionId = partitionId
    this.primary     = primary
    this.replicas    = replicas.toImmutable
  }

  override Str toStr()
  {
    repIds := replicas.map |r| { r.id }
    return "PartAssignment(id=$partitionId, primary=$primary.id, reps=$repIds)"
  }
}

**
** PartitionDiff: Tracks ownership changes between two partition table epochs.
**
const class PartitionDiff
{
  const Int oldEpoch
  const Int newEpoch
  const Int[] movedPartitions // Partitions whose primary owner changed
  const Int:NodeId newOwners // PartitionId -> new primary NodeId

  new make(Int oldEpoch, Int newEpoch, Int[] movedPartitions, Int:NodeId newOwners)
  {
    this.oldEpoch        = oldEpoch
    this.newEpoch        = newEpoch
    this.movedPartitions = movedPartitions.toImmutable
    this.newOwners       = newOwners.toImmutable
  }
}

**
** PartitionTable: Cluster routing table with epoch tracking and partition mapping.
**
** Features:
** - Maps keys deterministically to partition IDs: hash(key) % partitionCount.
** - Maintains primary and replica assignments for all partitions.
** - Epoch generation bumps upon every topology rebalance.
** - Computes partition migration diffs between epochs.
**
const class PartitionTable
{
  const Int epoch
  const Int partitionCount
  const Int replicaFactor
  const Int:PartitionAssignment assignments

  **
  ** Create partition table with explicit assignments and epoch.
  **
  new make(
    Int epoch,
    Int partitionCount,
    Int replicaFactor,
    Int:PartitionAssignment assignments)
  {
    this.epoch          = epoch
    this.partitionCount = partitionCount
    this.replicaFactor  = replicaFactor
    this.assignments    = assignments.toImmutable
  }

  **
  ** Build a fresh partition table by assigning partitions across nodes on a HashRing.
  **
  static PartitionTable buildFromRing(
    HashRing ring,
    Int partitionCount := 1024,
    Int replicaFactor := 2,
    Int epoch := 1)
  {
    assignments := Int:PartitionAssignment[:]
    for (p := 0; p < partitionCount; ++p)
    {
      partKey := "partition-$p"
      primary := ring.locatePrimary(partKey)
      if (primary == null) throw Err("Cannot build partition table: HashRing is empty")

      reps := ring.locateReplicas(partKey, replicaFactor)
      // Exclude primary from backup list
      backups := reps.findAll |NodeId n->Bool| { n != primary }

      assignments[p] = PartitionAssignment(p, primary, backups)
    }

    return PartitionTable(epoch, partitionCount, replicaFactor, assignments)
  }

  **
  ** Map key to partition ID.
  **
  Int getPartitionId(Str key)
  {
    hash := HashUtils.murmur3_32Str(key).and(0x7FFFFFFF)
    return hash % partitionCount
  }

  **
  ** Get assignment for a partition ID.
  **
  PartitionAssignment? getAssignment(Int partitionId)
  {
    return assignments[partitionId]
  }

  **
  ** Get primary owner for a key.
  **
  NodeId? getPrimary(Str key)
  {
    partId := getPartitionId(key)
    assign := assignments[partId]
    return assign != null ? assign.primary : null
  }

  **
  ** Get all replica nodes (including primary) for a key.
  **
  NodeId[] getAllReplicas(Str key)
  {
    partId := getPartitionId(key)
    assign := assignments[partId]
    if (assign == null) return NodeId[,]

    list := NodeId[,]
    list.add(assign.primary)
    list.addAll(assign.replicas)
    return list
  }

  **
  ** Compute ownership diff between this table and a target updated table.
  **
  PartitionDiff diff(PartitionTable target)
  {
    moved := Int[,]
    newOwners := Int:NodeId[:]

    assignments.each |currAssign, p|
    {
      targetAssign := target.assignments[p]
      if (targetAssign != null && currAssign.primary != targetAssign.primary)
      {
        moved.add(p)
        newOwners[p] = targetAssign.primary
      }
    }

    return PartitionDiff(this.epoch, target.epoch, moved, newOwners)
  }

  override Str toStr()
  {
    return "PartitionTable(epoch=$epoch, parts=$partitionCount, reps=$replicaFactor)"
  }
}
