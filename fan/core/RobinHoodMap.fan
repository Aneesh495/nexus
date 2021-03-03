**
** RobinHoodMap: Cache-conscious open-addressing hash table with Robin Hood displacement
** and backward-shift deletion.
**
** Key Properties:
** - Low variance in probe sequence length (PSL): "take from the rich, give to the poor".
** - Backward-shift deletion: eliminates tombstones and maintains contiguous probe clusters.
** - Flat array backing for optimal CPU cache line utilization.
** - High load factor tolerance (supports up to 0.88 without performance degradation).
**
class RobinHoodMap
{
  private Str?[] keys
  private Obj?[] vals
  private Int[] psls // -1 indicates empty slot
  private Int count := 0
  private Float maxLoadFactor := 0.85f

  **
  ** Create with initial capacity rounded up to the next power of two.
  **
  new make(Int initialCapacity := 16, Float maxLoadFactor := 0.85f)
  {
    cap := Bits.nextPowerOfTwo(initialCapacity.max(8))
    this.keys = Str?[,].fill(null, cap)
    this.vals = Obj?[,].fill(null, cap)
    this.psls = Int[,].fill(-1, cap)
    this.maxLoadFactor = maxLoadFactor
  }

  **
  ** Number of entries currently stored in the map.
  **
  Int size() { count }

  **
  ** Total allocated bucket capacity.
  **
  Int capacity() { keys.size }

  **
  ** Current load factor (count / capacity).
  **
  Float loadFactor() { count.toFloat / keys.size.toFloat }

  **
  ** Check if the map is empty.
  **
  Bool isEmpty() { count == 0 }

  **
  ** Clear all entries.
  **
  Void clear()
  {
    for (i := 0; i < keys.size; ++i)
    {
      keys[i] = null
      vals[i] = null
      psls[i] = -1
    }
    count = 0
  }

  **
  ** Retrieve value associated with key, or null if not found.
  **
  Obj? get(Str key)
  {
    mask := keys.size - 1
    ideal := HashUtils.murmur3_32Str(key).and(mask)
    currPsl := 0
    idx := ideal

    while (true)
    {
      slotPsl := psls[idx]
      if (slotPsl == -1 || currPsl > slotPsl)
      {
        return null // Not found: search terminates because entry would have displaced this slot
      }
      if (keys[idx] == key)
      {
        return vals[idx]
      }
      idx = (idx + 1).and(mask)
      currPsl++
    }
    return null
  }

  **
  ** Check if key exists in the map.
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
    if ((count + 1).toFloat / keys.size.toFloat >= maxLoadFactor)
    {
      rehash(keys.size * 2)
    }

    mask := keys.size - 1
    ideal := HashUtils.murmur3_32Str(key).and(mask)

    currKey := key
    currVal := val
    currPsl := 0
    idx := ideal

    while (true)
    {
      slotPsl := psls[idx]

      if (slotPsl == -1)
      {
        // Empty slot found: place entry
        keys[idx] = currKey
        vals[idx] = currVal
        psls[idx] = currPsl
        count++
        return null
      }

      if (keys[idx] == currKey)
      {
        // Key already exists: overwrite value
        oldVal := vals[idx]
        vals[idx] = currVal
        return oldVal
      }

      if (currPsl > slotPsl)
      {
        // Robin Hood displacement: current item is poorer than the occupant
        // Swap candidate with occupant and continue inserting the evicted occupant
        tmpKey := keys[idx]
        tmpVal := vals[idx]
        tmpPsl := psls[idx]

        keys[idx] = currKey
        vals[idx] = currVal
        psls[idx] = currPsl

        currKey = tmpKey
        currVal = tmpVal
        currPsl = tmpPsl
      }

      idx = (idx + 1).and(mask)
      currPsl++
    }
    return null
  }

  **
  ** Remove key and its associated value. Returns removed value or null.
  ** Uses backward-shift deletion to preserve optimal probe sequences without tombstones.
  **
  Obj? remove(Str key)
  {
    mask := keys.size - 1
    ideal := HashUtils.murmur3_32Str(key).and(mask)
    currPsl := 0
    idx := ideal

    while (true)
    {
      slotPsl := psls[idx]
      if (slotPsl == -1 || currPsl > slotPsl)
      {
        return null // Not found
      }
      if (keys[idx] == key)
      {
        oldVal := vals[idx]
        backwardShiftDelete(idx)
        count--
        return oldVal
      }
      idx = (idx + 1).and(mask)
      currPsl++
    }
    return null
  }

  **
  ** Iterate over all key-value pairs.
  **
  Void each(|Obj? val, Str key| f)
  {
    for (i := 0; i < keys.size; ++i)
    {
      if (psls[i] != -1 && keys[i] != null)
      {
        f(vals[i], keys[i])
      }
    }
  }

  **
  ** Return a list of all keys.
  **
  Str[] keysList()
  {
    list := Str[,]
    list.capacity = count
    each |_, k| { list.add(k) }
    return list
  }

  **
  ** Return a list of all values.
  **
  Obj?[] valsList()
  {
    list := Obj?[,]
    list.capacity = count
    each |v, _| { list.add(v) }
    return list
  }

  // --- Internal backward-shift deletion ---

  private Void backwardShiftDelete(Int removeIdx)
  {
    mask := keys.size - 1
    currIdx := removeIdx

    while (true)
    {
      nextIdx := (currIdx + 1).and(mask)
      nextPsl := psls[nextIdx]

      // Stop if next slot is empty or already in its ideal bucket (PSL == 0)
      if (nextPsl <= 0)
      {
        keys[currIdx] = null
        vals[currIdx] = null
        psls[currIdx] = -1
        break
      }

      // Shift backward
      keys[currIdx] = keys[nextIdx]
      vals[currIdx] = vals[nextIdx]
      psls[currIdx] = nextPsl - 1

      currIdx = nextIdx
    }
  }

  // --- Internal rehash ---

  private Void rehash(Int newCapacity)
  {
    oldKeys := keys
    oldVals := vals
    oldPsls := psls

    this.keys = Str?[,].fill(null, newCapacity)
    this.vals = Obj?[,].fill(null, newCapacity)
    this.psls = Int[,].fill(-1, newCapacity)
    this.count = 0

    for (i := 0; i < oldKeys.size; ++i)
    {
      if (oldPsls[i] != -1 && oldKeys[i] != null)
      {
        put(oldKeys[i], oldVals[i])
      }
    }
  }
}
