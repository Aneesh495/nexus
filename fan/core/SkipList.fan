**
** SkipList: Probabilistic sorted key-value index for fast range queries and prefix scans.
**
** Features:
** - O(log N) average search, insert, and delete complexity.
** - Forward pointer multi-level hierarchy with maximum 16 levels.
** - Range queries [fromKey, toKey) and prefix scans.
** - Deterministic iterator traversal in lexicographical order.
**
class SkipList
{
  private static const Int maxLevel := 16
  private static const Float probability := 0.5f

  private SkipNode head
  private Int currentLevel := 1
  private Int count := 0
  private FastRandom rng

  **
  ** Create empty skip list.
  **
  new make(Int seed := 42)
  {
    this.head = SkipNode("", null, maxLevel)
    this.rng = FastRandom(seed)
  }

  **
  ** Number of entries in the skip list.
  **
  Int size() { count }

  **
  ** Check if empty.
  **
  Bool isEmpty() { count == 0 }

  **
  ** Lookup value by key.
  **
  Obj? get(Str key)
  {
    SkipNode? curr := head
    for (i := currentLevel - 1; i >= 0; --i)
    {
      while (curr.forward[i] != null && curr.forward[i].key < key)
      {
        curr = curr.forward[i]
      }
    }
    curr = curr.forward[0]
    if (curr != null && curr.key == key)
    {
      return curr.val
    }
    return null
  }

  **
  ** Check if key exists.
  **
  Bool containsKey(Str key)
  {
    return get(key) != null
  }

  **
  ** Insert or update key-value mapping. Returns previous value if updated.
  **
  Obj? put(Str key, Obj? val)
  {
    update := SkipNode?[,].fill(null, maxLevel)
    SkipNode? curr := head

    for (i := currentLevel - 1; i >= 0; --i)
    {
      while (curr.forward[i] != null && curr.forward[i].key < key)
      {
        curr = curr.forward[i]
      }
      update[i] = curr
    }

    curr = curr.forward[0]
    if (curr != null && curr.key == key)
    {
      oldVal := curr.val
      curr.val = val
      return oldVal
    }

    // Insert new node
    lvl := randomLevel
    if (lvl > currentLevel)
    {
      for (i := currentLevel; i < lvl; ++i)
      {
        update[i] = head
      }
      currentLevel = lvl
    }

    newNode := SkipNode(key, val, lvl)
    for (i := 0; i < lvl; ++i)
    {
      newNode.forward[i] = update[i].forward[i]
      update[i].forward[i] = newNode
    }
    count++
    return null
  }

  **
  ** Remove key from skip list. Returns removed value or null.
  **
  Obj? remove(Str key)
  {
    update := SkipNode?[,].fill(null, maxLevel)
    SkipNode? curr := head

    for (i := currentLevel - 1; i >= 0; --i)
    {
      while (curr.forward[i] != null && curr.forward[i].key < key)
      {
        curr = curr.forward[i]
      }
      update[i] = curr
    }

    curr = curr.forward[0]
    if (curr == null || curr.key != key)
    {
      return null
    }

    for (i := 0; i < currentLevel; ++i)
    {
      if (update[i].forward[i] != curr) break
      update[i].forward[i] = curr.forward[i]
    }

    while (currentLevel > 1 && head.forward[currentLevel - 1] == null)
    {
      currentLevel--
    }

    count--
    return curr.val
  }

  **
  ** Retrieve entries within range [fromKey, toKey) up to limit.
  **
  Str:Obj? range(Str fromKey, Str toKey, Int limit := 100)
  {
    result := Str:Obj?[:]
    SkipNode? curr := head
    for (i := currentLevel - 1; i >= 0; --i)
    {
      while (curr.forward[i] != null && curr.forward[i].key < fromKey)
      {
        curr = curr.forward[i]
      }
    }
    curr = curr.forward[0]

    n := 0
    while (curr != null && curr.key < toKey && n < limit)
    {
      result[curr.key] = curr.val
      curr = curr.forward[0]
      n++
    }
    return result
  }

  **
  ** Scan entries starting with given prefix up to limit.
  **
  Str:Obj? prefixScan(Str prefix, Int limit := 100)
  {
    result := Str:Obj?[:]
    SkipNode? curr := head
    for (i := currentLevel - 1; i >= 0; --i)
    {
      while (curr.forward[i] != null && curr.forward[i].key < prefix)
      {
        curr = curr.forward[i]
      }
    }
    curr = curr.forward[0]

    n := 0
    while (curr != null && curr.key.startsWith(prefix) && n < limit)
    {
      result[curr.key] = curr.val
      curr = curr.forward[0]
      n++
    }
    return result
  }

  **
  ** Smallest key in the skip list, or null if empty.
  **
  Str? firstKey()
  {
    first := head.forward[0]
    return first == null ? null : first.key
  }

  **
  ** Largest key in the skip list, or null if empty.
  **
  Str? lastKey()
  {
    curr := head
    for (i := currentLevel - 1; i >= 0; --i)
    {
      while (curr.forward[i] != null)
      {
        curr = curr.forward[i]
      }
    }
    return curr == head ? null : curr.key
  }

  **
  ** Iterate in ascending sorted key order.
  **
  Void each(|Obj? val, Str key| f)
  {
    curr := head.forward[0]
    while (curr != null)
    {
      f(curr.val, curr.key)
      curr = curr.forward[0]
    }
  }

  private Int randomLevel()
  {
    lvl := 1
    while (rng.nextFloat < probability && lvl < maxLevel)
    {
      lvl++
    }
    return lvl
  }
}

**
** Internal node in SkipList hierarchy.
**
internal class SkipNode
{
  Str key
  Obj? val
  SkipNode?[] forward

  new make(Str key, Obj? val, Int level)
  {
    this.key = key
    this.val = val
    this.forward = SkipNode?[,].fill(null, level)
  }
}
