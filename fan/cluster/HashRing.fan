**
** HashRing: Consistent hash ring with configurable virtual nodes (vnodes).
**
** Properties:
** - Maps keys and nodes onto a 64-bit continuous token ring.
** - Uses MurmurHash3_64 for uniform token distribution.
** - Selects N distinct physical nodes for primary and secondary partition replicas.
** - Binary search lookup over sorted token list with wrap-around semantics.
**
class HashRing
{
  private Int vnodesPerNode
  private Int[] sortedTokens := Int[,]
  private Int:NodeId tokenToNode := Int:NodeId[:]
  private Str:NodeId activeNodes := Str:NodeId[:]

  **
  ** Create consistent hash ring with target vnodes per node (default: 256).
  **
  new make(Int vnodesPerNode := 256)
  {
    this.vnodesPerNode = vnodesPerNode.max(16)
  }

  **
  ** Add physical node to hash ring, populating its virtual nodes.
  **
  This addNode(NodeId node)
  {
    if (activeNodes.containsKey(node.id)) return this
    activeNodes[node.id] = node

    for (i := 0; i < vnodesPerNode; ++i)
    {
      vnodeTokenKey := "${node.id}#vnode-$i"
      token := HashUtils.murmur3_64Str(vnodeTokenKey)
      sortedTokens.add(token)
      tokenToNode[token] = node
    }

    sortedTokens.sort
    return this
  }

  **
  ** Remove physical node and all its virtual nodes from the ring.
  **
  This removeNode(NodeId node)
  {
    if (!activeNodes.containsKey(node.id)) return this
    activeNodes.remove(node.id)

    tokensToRemove := Int[,]
    for (i := 0; i < vnodesPerNode; ++i)
    {
      token := HashUtils.murmur3_64Str("${node.id}#vnode-$i")
      tokensToRemove.add(token)
      tokenToNode.remove(token)
    }

    sortedTokens.removeAll(tokensToRemove)
    return this
  }

  **
  ** Locate the primary owner node for a key. Returns null if ring is empty.
  **
  NodeId? locatePrimary(Str key)
  {
    if (sortedTokens.isEmpty) return null
    keyToken := HashUtils.murmur3_64Str(key)
    idx := findTokenIndex(keyToken)
    token := sortedTokens[idx]
    return tokenToNode[token]
  }

  **
  ** Locate distinct physical replica nodes for a key up to replicaCount.
  **
  NodeId[] locateReplicas(Str key, Int replicaCount)
  {
    if (sortedTokens.isEmpty || replicaCount <= 0) return NodeId[,]
    targetCount := replicaCount.min(activeNodes.size)
    replicas := NodeId[,]
    seen := Str:Bool[:]

    keyToken := HashUtils.murmur3_64Str(key)
    startIdx := findTokenIndex(keyToken)
    ringSize := sortedTokens.size

    for (step := 0; step < ringSize && replicas.size < targetCount; ++step)
    {
      currIdx := (startIdx + step) % ringSize
      token := sortedTokens[currIdx]
      node := tokenToNode[token]
      if (node != null && !seen.containsKey(node.id))
      {
        seen[node.id] = true
        replicas.add(node)
      }
    }

    return replicas
  }

  **
  ** Number of distinct physical nodes currently on the ring.
  **
  Int nodeCount() { activeNodes.size }

  **
  ** Total number of virtual nodes on the ring.
  **
  Int vnodeCount() { sortedTokens.size }

  **
  ** Clear all nodes from the ring.
  **
  Void clear()
  {
    sortedTokens.clear
    tokenToNode.clear
    activeNodes.clear
  }

  // Binary search for first token >= keyToken (wrapping around to 0 if keyToken > all tokens)
  private Int findTokenIndex(Int keyToken)
  {
    low := 0
    high := sortedTokens.size - 1

    if (keyToken > sortedTokens[high])
    {
      return 0 // Wrap around ring
    }

    while (low <= high)
    {
      mid := (low + high).shiftr(1)
      midVal := sortedTokens[mid]

      if (midVal >= keyToken)
      {
        high = mid - 1
      }
      else
      {
        low = mid + 1
      }
    }

    return low % sortedTokens.size
  }
}
