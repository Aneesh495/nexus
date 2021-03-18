**
** LruPolicy: Least Recently Used eviction algorithm based on a doubly-linked list.
**
** Recency is tracked by promoting accessed entries to the list head.
** Evictions are performed in O(1) time by taking from the list tail.
**
class LruPolicy : EvictionPolicy
{
  private Str:LruNode nodeMap := Str:LruNode[:]
  private LruNode? head := null
  private LruNode? tail := null

  override Void recordAccess(CacheEntry entry)
  {
    node := nodeMap[entry.key]
    if (node != null)
    {
      moveToHead(node)
    }
    else
    {
      recordInsert(entry)
    }
  }

  override Void recordInsert(CacheEntry entry)
  {
    existing := nodeMap[entry.key]
    if (existing != null)
    {
      moveToHead(existing)
      return
    }

    newNode := LruNode(entry.key)
    nodeMap[entry.key] = newNode
    attachHead(newNode)
  }

  override Void recordRemove(CacheEntry entry)
  {
    node := nodeMap.remove(entry.key)
    if (node != null)
    {
      detach(node)
    }
  }

  override Str? evictNext()
  {
    if (tail == null) return null
    victimKey := tail.key
    victimNode := nodeMap.remove(victimKey)
    if (victimNode != null)
    {
      detach(victimNode)
    }
    return victimKey
  }

  override Int size() { nodeMap.size }

  override Void clear()
  {
    nodeMap.clear
    head = null
    tail = null
  }

  private Void attachHead(LruNode node)
  {
    node.prev = null
    node.next = head
    if (head != null)
    {
      head.prev = node
    }
    head = node
    if (tail == null)
    {
      tail = node
    }
  }

  private Void detach(LruNode node)
  {
    if (node.prev != null) node.prev.next = node.next
    else head = node.next

    if (node.next != null) node.next.prev = node.prev
    else tail = node.prev

    node.prev = null
    node.next = null
  }

  private Void moveToHead(LruNode node)
  {
    if (node == head) return
    detach(node)
    attachHead(node)
  }
}

internal class LruNode
{
  Str key
  LruNode? prev
  LruNode? next

  new make(Str key)
  {
    this.key = key
  }
}
