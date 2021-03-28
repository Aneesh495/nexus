**
** TimingWheel: Hierarchical hashed timing wheel for high-throughput O(1) expiration scheduling.
**
** Reference:
** Varghese & Lauck, "Hashed and Hierarchical Timing Wheels: Data Structures
** for the Efficient Implementation of a Timer Facility", ACM TOCS 1987.
**
** Architecture:
** - Level 0: 512 slots x 10ms ticks (covers 0 to ~5.12 seconds)
** - Level 1: 64 slots x 5,120ms ticks (covers ~5.12s to ~327 seconds)
** - Level 2: 64 slots x 327,680ms ticks (covers ~5.4 minutes to ~5.8 hours)
** - Cascading: As coarse wheels advance, timers are re-scheduled into lower wheels.
**
class TimingWheel
{
  private static const Int wheel0Size := 512
  private static const Int tick0Millis := 10 // 10ms per tick

  private static const Int wheel1Size := 64
  private static const Int tick1Millis := wheel0Size * tick0Millis // 5120ms

  private static const Int wheel2Size := 64
  private static const Int tick2Millis := wheel1Size * tick1Millis // 327680ms

  private Str:WheelTimer timerIndex := Str:WheelTimer[:]
  private Int:Str:WheelTimer wheel0 := Int:Str:WheelTimer[:]
  private Int:Str:WheelTimer wheel1 := Int:Str:WheelTimer[:]
  private Int:Str:WheelTimer wheel2 := Int:Str:WheelTimer[:]

  private Int currentTickTime

  **
  ** Create timing wheel initialized at reference start time.
  **
  new make(Int startTimeMillis := DateTime.now.toJava)
  {
    this.currentTickTime = startTimeMillis
  }

  **
  ** Schedule an expiration deadline for a key. Returns true if scheduled.
  **
  Bool schedule(Str key, Int expireTimeMillis)
  {
    cancel(key)

    timer := WheelTimer(key, expireTimeMillis)
    timerIndex[key] = timer

    placeTimer(timer)
    return true
  }

  **
  ** Cancel an active timer for a key. Returns true if timer existed.
  **
  Bool cancel(Str key)
  {
    timer := timerIndex.remove(key)
    if (timer == null) return false

    removeFromBucket(timer)
    return true
  }

  **
  ** Advance the timing wheel to target timestamp and return all expired keys.
  **
  Str[] advance(Int nowMillis)
  {
    if (nowMillis < currentTickTime) return Str[,]
    expired := Str[,]

    while (currentTickTime <= nowMillis)
    {
      slot0 := (currentTickTime / tick0Millis) % wheel0Size
      bucket0 := wheel0.remove(slot0)

      if (bucket0 != null)
      {
        bucket0.each |timer, key|
        {
          if (timer.expireTime <= currentTickTime)
          {
            timerIndex.remove(key)
            expired.add(key)
          }
          else
          {
            // Re-place if not yet due
            placeTimer(timer)
          }
        }
      }

      // Check if Wheel 1 needs to cascade
      if (currentTickTime % tick1Millis == 0)
      {
        slot1 := (currentTickTime / tick1Millis) % wheel1Size
        bucket1 := wheel1.remove(slot1)
        if (bucket1 != null)
        {
          bucket1.each |timer, _| { placeTimer(timer) }
        }
      }

      // Check if Wheel 2 needs to cascade
      if (currentTickTime % tick2Millis == 0)
      {
        slot2 := (currentTickTime / tick2Millis) % wheel2Size
        bucket2 := wheel2.remove(slot2)
        if (bucket2 != null)
        {
          bucket2.each |timer, _| { placeTimer(timer) }
        }
      }

      currentTickTime += tick0Millis
    }

    return expired
  }

  **
  ** Number of currently scheduled timers.
  **
  Int size() { timerIndex.size }

  **
  ** Clear all timers.
  **
  Void clear()
  {
    timerIndex.clear
    wheel0.clear
    wheel1.clear
    wheel2.clear
  }

  private Void placeTimer(WheelTimer timer)
  {
    delay := timer.expireTime - currentTickTime
    if (delay <= 0)
    {
      // Immediate expiry: place in current wheel0 slot
      slot := (currentTickTime / tick0Millis) % wheel0Size
      addToBucket(wheel0, slot, timer)
    }
    else if (delay < tick1Millis)
    {
      slot := (timer.expireTime / tick0Millis) % wheel0Size
      addToBucket(wheel0, slot, timer)
      timer.level = 0
      timer.slot = slot
    }
    else if (delay < tick2Millis)
    {
      slot := (timer.expireTime / tick1Millis) % wheel1Size
      addToBucket(wheel1, slot, timer)
      timer.level = 1
      timer.slot = slot
    }
    else
    {
      slot := (timer.expireTime / tick2Millis) % wheel2Size
      addToBucket(wheel2, slot, timer)
      timer.level = 2
      timer.slot = slot
    }
  }

  private Void addToBucket(Int:Str:WheelTimer buckets, Int slot, WheelTimer timer)
  {
    b := buckets[slot]
    if (b == null)
    {
      b = Str:WheelTimer[:]
      buckets[slot] = b
    }
    b[timer.key] = timer
  }

  private Void removeFromBucket(WheelTimer timer)
  {
    if (timer.level == 0)
    {
      b := wheel0[timer.slot]
      if (b != null) b.remove(timer.key)
    }
    else if (timer.level == 1)
    {
      b := wheel1[timer.slot]
      if (b != null) b.remove(timer.key)
    }
    else if (timer.level == 2)
    {
      b := wheel2[timer.slot]
      if (b != null) b.remove(timer.key)
    }
  }
}

internal class WheelTimer
{
  Str key
  Int expireTime
  Int level := 0
  Int slot := 0

  new make(Str key, Int expireTime)
  {
    this.key = key
    this.expireTime = expireTime
  }
}
