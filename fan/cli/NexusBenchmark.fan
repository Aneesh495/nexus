**
** High-throughput benchmarking tool measuring latency percentiles (p50, p95, p99)
** and operations per second across concurrent client pipelines.
**
class NexusBenchmark
{
  **
  ** Run in-memory or socket-based synthetic load test.
  ** Returns map of metrics: opsPerSec, p50Millis, p95Millis, p99Millis.
  **
  static Str:Float runBenchmark(Int operationCount := 5000, Str:Obj? options := [:])
  {
    store := PartitionStore(0, 100000, 100 * 1024 * 1024)
    dispatcher := RespCommandDispatcher(store)

    Float[] latencies := Float[,]
    FastRandom rng := FastRandom(42)

    startTime := Duration.now

    for (i := 0; i < operationCount; ++i)
    {
      t0 := Duration.now
      key := "benchmark:key:${rng.nextInt(1000)}"

      if (rng.nextBool)
      {
        // SET operation
        val := "payload-value-${i}"
        cmd := RespValue.array([
          RespValue.bulkString("SET"),
          RespValue.bulkString(key),
          RespValue.bulkString(val)
        ])
        dispatcher.dispatch(cmd)
      }
      else
      {
        // GET operation
        cmd := RespValue.array([
          RespValue.bulkString("GET"),
          RespValue.bulkString(key)
        ])
        dispatcher.dispatch(cmd)
      }

      t1 := Duration.now
      latencyMs := (t1 - t0).toMillis.toFloat
      latencies.add(latencyMs)
    }

    totalDuration := Duration.now - startTime
    totalSec := totalDuration.toMillis.toFloat / 1000.0f
    if (totalSec <= 0.0f) totalSec = 0.001f

    opsPerSec := operationCount.toFloat / totalSec

    latencies.sort

    p50 := latencies[(latencies.size.toFloat * 0.50f).round.toInt.min(latencies.size - 1)]
    p95 := latencies[(latencies.size.toFloat * 0.95f).round.toInt.min(latencies.size - 1)]
    p99 := latencies[(latencies.size.toFloat * 0.99f).round.toInt.min(latencies.size - 1)]

    return [
      "opsPerSec": opsPerSec,
      "p50Millis": p50,
      "p95Millis": p95,
      "p99Millis": p99,
      "totalSec": totalSec
    ]
  }

  static Void main(Str[] args)
  {
    ops := 10000
    for (i := 0; i < args.size; ++i)
    {
      if ((args[i] == "-n" || args[i] == "--num") && i + 1 < args.size)
        ops = args[i + 1].toInt
    }

    echo("Starting Nexus Benchmark ($ops operations)...")
    results := runBenchmark(ops)

    echo("-----------------------------------------------------------------")
    echo("Benchmark Results:")
    echo("  Total Operations: " + ops)
    echo("  Throughput:       " + results["opsPerSec"].round.toInt + " ops/sec")
    echo("  p50 Latency:      " + results["p50Millis"].toLocale("0.00") + " ms")
    echo("  p95 Latency:      " + results["p95Millis"].toLocale("0.00") + " ms")
    echo("  p99 Latency:      " + results["p99Millis"].toLocale("0.00") + " ms")
    echo("-----------------------------------------------------------------")
  }
}
