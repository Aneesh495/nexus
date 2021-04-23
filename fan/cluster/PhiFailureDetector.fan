**
** PhiFailureDetector: Adaptive accrual failure detector based on normal distribution CDF.
**
** Reference:
** Hayashibara, Defago, Yared, Katayama, "The Phi Accrual Failure Detector",
** IEEE Symposium on Reliable Distributed Systems (SRDS) 2004.
**
** Formula:
** phi = -log10(P_later(t - t_last))
**
** In contrast to rigid heartbeat timeouts, the accrual failure detector outputs
** a continuous suspicion level phi that adapts dynamically to network jitter and GC pauses.
**
class PhiFailureDetector
{
  private static const Int minSampleCount := 5
  private static const Int maxSampleCount := 1000

  private Str:HeartbeatHistory historyMap := Str:HeartbeatHistory[:]
  private Float threshold
  private Float minStdDev

  **
  ** Create failure detector with target suspicion threshold and minimum standard deviation.
  **
  new make(Float threshold := 8.0f, Float minStdDev := 100.0f)
  {
    this.threshold = threshold
    this.minStdDev  = minStdDev
  }

  **
  ** Record heartbeat arrival from a node.
  **
  Void heartbeat(Str nodeId, Int timestamp := DateTime.now.toJava)
  {
    hist := historyMap[nodeId]
    if (hist == null)
    {
      hist = HeartbeatHistory(nodeId, timestamp)
      historyMap[nodeId] = hist
      return
    }

    interval := (timestamp - hist.lastHeartbeat).max(1)
    hist.addInterval(interval)
    hist.lastHeartbeat = timestamp
  }

  **
  ** Calculate suspicion metric phi for a node at given timestamp.
  **
  Float phi(Str nodeId, Int nowMillis := DateTime.now.toJava)
  {
    hist := historyMap[nodeId]
    if (hist == null) return 0.0f

    timeDiff := (nowMillis - hist.lastHeartbeat).max(0)
    if (hist.intervals.size < minSampleCount)
    {
      // Not enough historical samples: use bootstrap conservative estimate
      return timeDiff > 10_000 ? 12.0f : 0.0f
    }

    mean := hist.mean
    stdDev := hist.stdDev.max(minStdDev)

    // Compute probability using Gaussian tail approximation
    y := (timeDiff.toFloat - mean) / stdDev
    e := (-y * (1.5976f + 0.070566f * y * y)).exp
    pLater := 0.0f

    if (timeDiff.toFloat > mean)
    {
      pLater = e / (1.0f + e)
    }
    else
    {
      pLater = 1.0f - (1.0f / (1.0f + e))
    }

    // Clamp probability
    pLater = pLater.max(0.0000000000000001f).min(1.0f)
    phiVal := -1.0f * (pLater.log / 10.0f.log)
    return phiVal.max(0.0f)
  }

  **
  ** Check if node is considered healthy (phi < threshold).
  **
  Bool isAvailable(Str nodeId, Int nowMillis := DateTime.now.toJava)
  {
    return phi(nodeId, nowMillis) < threshold
  }

  **
  ** Remove node tracking history.
  **
  Void remove(Str nodeId)
  {
    historyMap.remove(nodeId)
  }

  **
  ** Clear all tracking history.
  **
  Void clear()
  {
    historyMap.clear
  }
}

internal class HeartbeatHistory
{
  Str nodeId
  Int lastHeartbeat
  Int[] intervals := Int[,]
  Int intervalSum := 0
  Int intervalSumSq := 0

  new make(Str nodeId, Int initialHeartbeat)
  {
    this.nodeId        = nodeId
    this.lastHeartbeat = initialHeartbeat
  }

  Void addInterval(Int interval)
  {
    intervals.add(interval)
    intervalSum += interval
    intervalSumSq += interval * interval

    if (intervals.size > 1000)
    {
      oldest := intervals.removeAt(0)
      intervalSum -= oldest
      intervalSumSq -= oldest * oldest
    }
  }

  Float mean()
  {
    if (intervals.isEmpty) return 1000.0f
    return intervalSum.toFloat / intervals.size.toFloat
  }

  Float variance()
  {
    if (intervals.size < 2) return 100.0f
    m := mean
    v := (intervalSumSq.toFloat / intervals.size.toFloat) - (m * m)
    return v.max(1.0f)
  }

  Float stdDev()
  {
    return variance.sqrt
  }
}
