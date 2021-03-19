**
** ClockPolicy: Second-chance circular eviction algorithm.
**
** Uses a clock hand scanning a circular list of entries. Entries accessed since the
** last pass are given a second chance by resetting their reference bit from 1 to 0.
** The first entry encountered with a reference bit of 0 is evicted.
**
class ClockPolicy : EvictionPolicy
{
  private ClockNode[] nodes := ClockNode[,]
  private Str:ClockNode nodeMap := Str:ClockNode[:]
  private Int hand := 0

  override Void recordAccess(CacheEntry entry)
  {
    node := nodeMap[entry.key]
    if (node != null)
    {
      node.refBit = true
    }
    else
    {
      recordInsert(entry)
    }
  }

  override Void recordInsert(CacheEntry entry)
  {
    node := nodeMap[entry.key]
    if (node != null)
    {
      node.refBit = true
      return
    }

    newNode := ClockNode(entry.key, true)
    nodeMap[entry.key] = newNode
    nodes.add(newNode)
  }

  override Void recordRemove(CacheEntry entry)
  {
    node := nodeMap.remove(entry.key)
    if (node != null)
    {
      idx := nodes.findIndex |n| { n.key == entry.key }
      if (idx != null)
      {
        nodes.removeAt(idx)
        if (hand >= nodes.size && !nodes.isEmpty)
        {
          hand = 0
        }
      }
    }
  }

  override Str? evictNext()
  {
    if (nodes.isEmpty) return null
    sweeps := 0
    maxSweeps := nodes.size * 2 + 2

    while (sweeps < maxSweeps)
    {
      if (hand >= nodes.size) hand = 0
      curr := nodes[hand]

      if (curr.refBit)
      {
        // Second chance granted: clear bit and advance hand
        curr.refBit = false
        hand++
        sweeps++
      }
      else
      {
        // Victim found
        victimKey := curr.key
        nodes.removeAt(hand)
        nodeMap.remove(victimKey)
        if (hand >= nodes.size && !nodes.isEmpty)
        {
          hand = 0
        }
        return victimKey
      }
    }

    // Fallback: evict whatever is under the hand
    if (nodes.isEmpty) return null
    if (hand >= nodes.size) hand = 0
    victimKey := nodes[hand].key
    nodes.removeAt(hand)
    nodeMap.remove(victimKey)
    return victimKey
  }

  override Int size() { nodeMap.size }

  override Void clear()
  {
    nodes.clear
    nodeMap.clear
    hand = 0
  }
}

internal class ClockNode
{
  Str key
  Bool refBit

  new make(Str key, Bool refBit := true)
  {
    this.key = key
    this.refBit = refBit
  }
}
