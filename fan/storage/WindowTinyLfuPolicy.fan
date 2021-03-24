**
** WindowTinyLfuPolicy: State-of-the-art cache admission and eviction architecture.
**
** Reference:
** Einziger, Friedman, Manassiev, "TinyLFU: A Highly Efficient Cache Admission Policy",
** ACM Transactions on Storage, 2017.
**
** Components:
** 1. Window LRU (1% of capacity): Admits new entries to absorb bursty recency workloads.
** 2. CountMinSketch Frequency Filter: 4-bit saturated frequency estimator with halving reset.
** 3. Main Cache (99% of capacity) using Segmented LRU (SLRU):
**    - Probation Segment (20% of main): Newly promoted entries.
**    - Protected Segment (80% of main): Multi-access entries protected from eviction.
** 4. TinyLFU Admission Duel: When cache is full, the window victim competes against the
**    probation victim. Candidate with higher frequency wins admission.
** 5. Adaptive Hill Climbing: Dynamically tunes window size based on hit ratio trends.
**
class WindowTinyLfuPolicy : EvictionPolicy
{
  private Int maxCapacity
  private CountMinSketch sketch

  // Window LRU
  private LruPolicy windowLru := LruPolicy()
  private Int windowCap

  // Main Segmented LRU: Probation + Protected
  private LruPolicy probationLru := LruPolicy()
  private LruPolicy protectedLru := LruPolicy()
  private Int probationCap
  private Int protectedCap

  // Master key-to-segment index
  private Str:Int segmentMap := Str:Int[:] // 0 = Window, 1 = Probation, 2 = Protected

  // Hill climbing metrics
  private Int windowHits := 0
  private Int mainHits := 0
  private Int stepSize := 1

  **
  ** Create W-TinyLFU policy for given maximum capacity.
  **
  new make(Int maxCapacity)
  {
    this.maxCapacity = maxCapacity.max(16)
    this.sketch = CountMinSketch(this.maxCapacity)

    // Initial allocations: Window 1%, Main 99% (Probation 20%, Protected 80%)
    wSize := (this.maxCapacity / 100).max(1)
    mainSize := this.maxCapacity - wSize
    this.windowCap    = wSize
    this.probationCap = (mainSize * 20 / 100).max(1)
    this.protectedCap = mainSize - this.probationCap
  }

  override Void recordAccess(CacheEntry entry)
  {
    sketch.increment(entry.key)
    seg := segmentMap[entry.key]

    if (seg == null)
    {
      recordInsert(entry)
      return
    }

    if (seg == 0)
    {
      windowHits++
      windowLru.recordAccess(entry)
    }
    else if (seg == 1)
    {
      mainHits++
      // Promote from probation to protected
      probationLru.recordRemove(entry)
      protectedLru.recordInsert(entry)
      segmentMap[entry.key] = 2

      // Check if protected segment exceeded capacity: demote LRU to probation
      if (protectedLru.size > protectedCap)
      {
        demoteKey := protectedLru.evictNext
        if (demoteKey != null)
        {
          demoteEntry := CacheEntry(demoteKey, null, entry.version)
          probationLru.recordInsert(demoteEntry)
          segmentMap[demoteKey] = 1
        }
      }
    }
    else if (seg == 2)
    {
      mainHits++
      protectedLru.recordAccess(entry)
    }
  }

  override Void recordInsert(CacheEntry entry)
  {
    sketch.increment(entry.key)

    if (segmentMap.containsKey(entry.key))
    {
      recordAccess(entry)
      return
    }

    // Always admit new arrivals into the Window LRU
    windowLru.recordInsert(entry)
    segmentMap[entry.key] = 0
  }

  override Void recordRemove(CacheEntry entry)
  {
    seg := segmentMap.remove(entry.key)
    if (seg == 0) windowLru.recordRemove(entry)
    else if (seg == 1) probationLru.recordRemove(entry)
    else if (seg == 2) protectedLru.recordRemove(entry)
  }

  override Str? evictNext()
  {
    // Step 1: If window cache is over capacity, evict its LRU candidate
    if (windowLru.size > windowCap)
    {
      candKey := windowLru.evictNext
      if (candKey == null) return null
      segmentMap.remove(candKey)

      // If main cache has space, admit candidate directly into probation
      if (probationLru.size + protectedLru.size < probationCap + protectedCap)
      {
        probationLru.recordInsert(CacheEntry(candKey, null, HybridLogicalClock.zero))
        segmentMap[candKey] = 1
        return null // Admitted into probation without global eviction
      }

      // Main cache is full: duel candidate against probation victim
      victimKey := probationLru.evictNext
      if (victimKey == null)
      {
        // Fallback: evict candidate
        return candKey
      }
      segmentMap.remove(victimKey)

      candFreq := sketch.estimate(candKey)
      victimFreq := sketch.estimate(victimKey)

      if (candFreq > victimFreq)
      {
        // Candidate wins: admit to probation, evict probation victim
        probationLru.recordInsert(CacheEntry(candKey, null, HybridLogicalClock.zero))
        segmentMap[candKey] = 1
        return victimKey
      }
      else
      {
        // Victim wins: preserve victim in probation, evict window candidate
        probationLru.recordInsert(CacheEntry(victimKey, null, HybridLogicalClock.zero))
        segmentMap[victimKey] = 1
        return candKey
      }
    }

    // Step 2: If main probation is over capacity
    if (probationLru.size > 0)
    {
      vKey := probationLru.evictNext
      if (vKey != null) segmentMap.remove(vKey)
      return vKey
    }

    // Step 3: Evict from window if available
    wKey := windowLru.evictNext
    if (wKey != null) segmentMap.remove(wKey)
    return wKey
  }

  override Int size()
  {
    return windowLru.size + probationLru.size + protectedLru.size
  }

  override Void clear()
  {
    windowLru.clear
    probationLru.clear
    protectedLru.clear
    segmentMap.clear
    sketch.clear
    windowHits = 0
    mainHits = 0
  }

  **
  ** Adapt window size dynamically using hill climbing based on hit telemetry.
  **
  Void adaptWindowSize()
  {
    totalHits := windowHits + mainHits
    if (totalHits > 100)
    {
      if (windowHits > mainHits)
      {
        // Favor recency: expand window size up to 25% of total capacity
        maxWindow := (maxCapacity * 25 / 100).max(1)
        if (windowCap + stepSize <= maxWindow)
        {
          windowCap += stepSize
          probationCap = (probationCap - stepSize).max(1)
        }
      }
      else
      {
        // Favor frequency: shrink window size down to 1% of total capacity
        minWindow := (maxCapacity / 100).max(1)
        if (windowCap - stepSize >= minWindow)
        {
          windowCap -= stepSize
          probationCap += stepSize
        }
      }
      windowHits = 0
      mainHits = 0
    }
  }

  **
  ** Return current window capacity.
  **
  Int currentWindowCap() { windowCap }
}
