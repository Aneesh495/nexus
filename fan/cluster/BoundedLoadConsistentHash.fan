**
** BoundedLoadConsistentHash: Consistent hashing with strict per-node capacity bounds.
**
** Reference:
** Mirrokni, Thorup, Zadimoghaddam, "Consistent Hashing with Bounded Loads",
** ACM Symposium on Theory of Computing (STOC) 2017.
**
** Problem Solved:
** Standard consistent hashing cannot bound the maximum load of individual nodes,
** leading to hot spot failures where one node handles 2x-5x the average load.
**
** Solution:
** Enforces maximum load bound: L = ceil((1 + epsilon) * (totalKeys / nodeCount)).
** If the primary hash node is at capacity L, the algorithm walks clockwise along
** the ring to the next available node whose current load is below L.
**
class BoundedLoadConsistentHash
{
  private HashRing ring
  private Float epsilon
  private Str:Int nodeLoads := Str:Int[:]
  private Int totalAssignedKeys := 0

  **
  ** Create bounded-load router with target epsilon (load slack factor, default: 0.25).
  **
  new make(HashRing ring, Float epsilon := 0.25f)
  {
    this.ring = ring
    this.epsilon = epsilon.max(0.05f)
  }

  **
  ** Calculate the maximum permitted load per node given total assigned keys.
  **
  Int maxCapacityPerNode()
  {
    n := ring.nodeCount
    if (n == 0) return 0
    avgLoad := totalAssignedKeys.toFloat / n.toFloat
    bound := ((1.0f + epsilon) * avgLoad).ceil.toInt
    return bound.max(1)
  }

  **
  ** Assign a key to a node under strict bounded load constraints.
  ** Returns assigned NodeId.
  **
  NodeId? assignKey(Str key)
  {
    if (ring.nodeCount == 0) return null
    capacityBound := maxCapacityPerNode

    // Retrieve replicas in clockwise ring order
    candidates := ring.locateReplicas(key, ring.nodeCount)
    for (i := 0; i < candidates.size; ++i)
    {
      candidate := candidates[i]
      currLoad := nodeLoads.get(candidate.id, 0)
      if (currLoad < capacityBound)
      {
        nodeLoads[candidate.id] = currLoad + 1
        totalAssignedKeys++
        return candidate
      }
    }

    // Fallback if all nodes are at capacityBound: assign to minimum loaded candidate
    minNode := candidates[0]
    minLoad := nodeLoads.get(minNode.id, 0)
    for (i := 1; i < candidates.size; ++i)
    {
      l := nodeLoads.get(candidates[i].id, 0)
      if (l < minLoad)
      {
        minLoad = l
        minNode = candidates[i]
      }
    }

    nodeLoads[minNode.id] = minLoad + 1
    totalAssignedKeys++
    return minNode
  }

  **
  ** Release a key from a node when deleted or migrated.
  **
  Void releaseKey(NodeId node)
  {
    curr := nodeLoads.get(node.id, 0)
    if (curr > 0)
    {
      nodeLoads[node.id] = curr - 1
      totalAssignedKeys--
    }
  }

  **
  ** Current load of specified node.
  **
  Int getLoad(NodeId node)
  {
    return nodeLoads.get(node.id, 0)
  }

  **
  ** Reset all load tracking metrics.
  **
  Void reset()
  {
    nodeLoads.clear
    totalAssignedKeys = 0
  }
}
