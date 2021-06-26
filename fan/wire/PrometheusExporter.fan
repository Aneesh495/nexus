**
** Formats cluster telemetry, storage metrics, and Raft consensus statistics
** into standard Prometheus exposition text format (version 0.0.4).
**
class PrometheusExporter
{
  **
  ** Render a full Prometheus metrics scrape response from current cluster metrics.
  **
  static Str renderMetrics(
    Int clusterNodes,
    Int keyspaceEntries,
    Int memoryBytes,
    Int totalOps,
    Int raftTerm := 1,
    Int raftCommitIndex := 0,
    Int activeTransactions := 0)
  {
    buf := StrBuf(1024)

    appendGauge(buf, "nexus_cluster_nodes", "Total active nodes registered in cluster topology", clusterNodes)
    appendGauge(buf, "nexus_keyspace_entries", "Total entries stored across memory partitions", keyspaceEntries)
    appendGauge(buf, "nexus_memory_bytes", "Total estimated memory footprint in bytes", memoryBytes)
    appendCounter(buf, "nexus_operations_total", "Cumulative number of operations processed", totalOps)
    appendGauge(buf, "nexus_raft_term", "Current Raft consensus election term", raftTerm)
    appendGauge(buf, "nexus_raft_commit_index", "Monotonic Raft consensus commit index", raftCommitIndex)
    appendGauge(buf, "nexus_active_transactions", "Number of currently active 2PC transactions", activeTransactions)

    return buf.toStr
  }

  private static Void appendGauge(StrBuf buf, Str name, Str help, Int val)
  {
    buf.add("# HELP ").add(name).add(" ").add(help).add("\n")
    buf.add("# TYPE ").add(name).add(" gauge\n")
    buf.add(name).add(" ").add(val.toStr).add("\n")
  }

  private static Void appendCounter(StrBuf buf, Str name, Str help, Int val)
  {
    buf.add("# HELP ").add(name).add(" ").add(help).add("\n")
    buf.add("# TYPE ").add(name).add(" counter\n")
    buf.add(name).add(" ").add(val.toStr).add("\n")
  }
}
