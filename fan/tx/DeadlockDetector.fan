**
** Deadlock victim selection policy when a cycle is detected in the wait-for graph.
**
enum class VictimPolicy
{
  ** Abort the youngest transaction (highest timestamp) to preserve senior work **
  youngest,

  ** Abort the transaction with the fewest locked resources **
  leastWork
}

**
** Directed wait-for graph with cycle detection and automated victim selection.
** Employs depth-first search with three-state node coloring (unvisited, visiting, visited)
** to discover directed cycles in O(V + E) time.
**
class DeadlockDetector
{
  private VictimPolicy policy
  private TxId:TxId[] waitGraph := TxId:TxId[][:]
  private TxId:Int lockCounts := TxId:Int[:]

  ** Construct a DeadlockDetector with the specified victim selection policy **
  new make(VictimPolicy policy := VictimPolicy.youngest)
  {
    this.policy = policy
  }

  ** Register a transaction with its current lock acquisition count **
  Void registerTx(TxId tx, Int lockCount := 0)
  {
    lockCounts[tx] = lockCount
    if (!waitGraph.containsKey(tx))
      waitGraph[tx] = TxId[,]
  }

  ** Record that waitingTx is blocked waiting for a lock held by holdingTx **
  Void addWaitEdge(TxId waitingTx, TxId holdingTx)
  {
    registerTx(waitingTx, lockCounts.get(waitingTx, 0))
    registerTx(holdingTx, lockCounts.get(holdingTx, 0))

    TxId[] targets := waitGraph[waitingTx]
    if (!targets.contains(holdingTx))
      targets.add(holdingTx)
  }

  ** Remove a specific wait dependency between two transactions **
  Void removeWaitEdge(TxId waitingTx, TxId holdingTx)
  {
    TxId[]? targets := waitGraph[waitingTx]
    if (targets != null)
      targets.remove(holdingTx)
  }

  ** Remove a transaction completely upon commit or abort **
  Void removeTx(TxId tx)
  {
    waitGraph.remove(tx)
    lockCounts.remove(tx)

    // Remove as target in other node adjacency lists
    waitGraph.each |targets, src|
    {
      targets.remove(tx)
    }
  }

  ** Get current number of transactions tracked in the graph **
  Int txCount() { waitGraph.size }

  ** Check whether an edge exists from waitingTx to holdingTx **
  Bool hasEdge(TxId waitingTx, TxId holdingTx)
  {
    TxId[]? targets := waitGraph[waitingTx]
    if (targets == null) return false
    return targets.contains(holdingTx)
  }

  **
  ** Discover all directed cycles currently present in the wait-for graph.
  ** Each returned cycle is a list of TxIds forming the circular dependency.
  **
  List[] findCycles()
  {
    TxId:Int color := TxId:Int[:] // 0: White (unvisited), 1: Gray (visiting), 2: Black (visited)
    TxId:TxId parent := TxId:TxId[:]
    List[] cycles := List[,]

    TxId[] allNodes := waitGraph.keys

    for (i := 0; i < allNodes.size; ++i)
    {
      node := allNodes[i]
      if (color.get(node, 0) == 0)
      {
        dfsVisit(node, color, parent, cycles)
      }
    }

    return cycles
  }

  private Void dfsVisit(TxId u, TxId:Int color, TxId:TxId parent, List[] cycles)
  {
    color[u] = 1 // Gray: in current recursion stack
    TxId[] edges := waitGraph.get(u, TxId[,])

    for (i := 0; i < edges.size; ++i)
    {
      v := edges[i]
      nodeColor := color.get(v, 0)
      if (nodeColor == 1)
      {
        // Cycle detected: reconstruct cycle from u back to v
        TxId[] cycle := TxId[,]
        curr := u
        cycle.add(curr)

        while (curr != v && parent.containsKey(curr))
        {
          curr = parent[curr]
          cycle.add(curr)
        }

        // Reverse to get correct forward order
        cycle = cycle.reverse
        cycles.add(cycle)
      }
      else if (nodeColor == 0)
      {
        parent[v] = u
        dfsVisit(v, color, parent, cycles)
      }
    }

    color[u] = 2 // Black: fully explored
  }

  **
  ** Choose the optimal victim transaction to abort within a detected cycle.
  **
  TxId selectVictim(TxId[] cycle)
  {
    if (cycle.isEmpty) throw ArgErr("Cycle cannot be empty")
    if (cycle.size == 1) return cycle.first

    switch (policy)
    {
      case VictimPolicy.leastWork:
        TxId minTx := cycle.first
        Int minLocks := lockCounts.get(minTx, 0)
        for (i := 1; i < cycle.size; ++i)
        {
          candidate := cycle[i]
          locks := lockCounts.get(candidate, 0)
          if (locks < minLocks)
          {
            minLocks = locks
            minTx = candidate
          }
        }
        return minTx

      case VictimPolicy.youngest:
      default:
        // Highest timestamp (or highest sequence if timestamps match)
        TxId youngest := cycle.first
        for (i := 1; i < cycle.size; ++i)
        {
          candidate := cycle[i]
          if (candidate.timestamp > youngest.timestamp)
          {
            youngest = candidate
          }
          else if (candidate.timestamp == youngest.timestamp && candidate.sequence > youngest.sequence)
          {
            youngest = candidate
          }
        }
        return youngest
    }
  }

  **
  ** Scan for deadlocks, select victims, purge their edges, and return
  ** the list of aborted victim transactions.
  **
  TxId[] resolveDeadlocks()
  {
    TxId[] victims := TxId[,]

    while (true)
    {
      List[] cycles := findCycles()
      if (cycles.isEmpty) break

      TxId[] firstCycle := cycles.first
      TxId victim := selectVictim(firstCycle)
      victims.add(victim)
      removeTx(victim)
    }

    return victims
  }
}
