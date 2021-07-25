# Nexus Wire Protocols Specification
## RESP3, Binary Transport, and HTTP/REST Standards

Nexus features a multi-protocol network gateway that natively multiplexes Redis RESP2/RESP3, custom high-speed binary RPC, and HTTP 1.1 REST on the same TCP port.

---

### 1. Redis Serialization Protocol (RESP2 / RESP3)

Nexus is fully compatible with standard Redis client libraries across all major languages.

#### Data Type Prefix Reference
| Prefix | Type | Format | Example |
|---|---|---|---|
| `+` | Simple String | `+<str>\r\n` | `+OK\r\n` |
| `-` | Error | `-<msg>\r\n` | `-ERR unknown command\r\n` |
| `:` | Integer | `:<num>\r\n` | `:42\r\n` |
| `$` | Bulk String | `$<len>\r\n<data>\r\n` | `$5\r\nhello\r\n` |
| `$` | Null Bulk String | `$-1\r\n` | `$-1\r\n` |
| `*` | Array | `*<count>\r\n...` | `*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n` |
| `*` | Null Array | `*-1\r\n` | `*-1\r\n` |
| `#` | Boolean (RESP3) | `#t\r\n` or `#f\r\n` | `#t\r\n` |
| `,` | Double (RESP3) | `,<float>\r\n` | `,3.14159\r\n` |
| `_` | Null (RESP3) | `_\r\n` | `_\r\n` |

#### Supported Command Matrix
- **Key-Value**: `GET`, `SET`, `SETNX`, `MGET`, `MSET`, `DEL`, `EXISTS`, `EXPIRE`, `TTL`, `INCR`, `DECR`, `INCRBY`, `DECRBY`
- **Hashes**: `HSET`, `HGET`, `HDEL`, `HLEN`, `HGETALL`
- **Lists**: `LPUSH`, `RPUSH`, `LPOP`, `RPOP`, `LLEN`
- **Sets**: `SADD`, `SMEMBERS`, `SISMEMBER`, `SCARD`
- **Cluster & Management**: `PING`, `ECHO`, `INFO`, `DBSIZE`, `FLUSHDB`, `CLUSTER NODES`, `CLUSTER INFO`

---

### 2. High-Speed Binary RPC Protocol

For node-to-node Raft consensus and high-throughput internal RPC, Nexus uses a binary frame with hardware-accelerated CRC32C validation:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Magic (0x4E455853 "NEXS")                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    Version    |     Flags     |          Message Type         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     Correlation Identifier                    |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Payload Length                         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     Castagnoli CRC32C                         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Payload Bytes ...                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

#### Frame Fields
- `Magic` (32-bit): Constant `0x4E455853` ("NEXS") verifying stream alignment.
- `Version` (8-bit): Protocol version (currently 1).
- `Flags` (8-bit): Bit 0 = Response, Bit 1 = Compressed, Bit 2 = Heartbeat, Bit 3 = Oneway.
- `Message Type` (16-bit): Identifies operation (1=Ping, 2=Pong, 3=Get, 4=Put, 5=Del, 10=RaftRpc, 20=TxPrepare, 99=Error).
- `Correlation ID` (64-bit): Monotonic request identifier for non-blocking asynchronous pipelining.
- `Payload Length` (32-bit): Length of body in bytes.
- `CRC32C` (32-bit): Castagnoli checksum computed over payload bytes.

---

### 3. HTTP 1.1 REST & Prometheus Observability

Nexus provides RESTful HTTP 1.1 endpoints for metrics scraping and administrative operations:

#### Scrape Endpoint: `GET /metrics`
Exposes system telemetry in Prometheus text format (version 0.0.4):
```
# HELP nexus_cluster_nodes Total active nodes registered in cluster topology
# TYPE nexus_cluster_nodes gauge
nexus_cluster_nodes 3
# HELP nexus_keyspace_entries Total entries stored across memory partitions
# TYPE nexus_keyspace_entries gauge
nexus_keyspace_entries 150000
# HELP nexus_memory_bytes Total estimated memory footprint in bytes
# TYPE nexus_memory_bytes gauge
nexus_memory_bytes 41943040
# HELP nexus_operations_total Cumulative number of operations processed
# TYPE nexus_operations_total counter
nexus_operations_total 128450
```

#### Health Check: `GET /healthz`
Returns cluster health status:
```json
{
  "status": "UP",
  "cluster_nodes": 3,
  "keys": 150000
}
```

#### Embedded Console: `GET /` or `GET /dashboard`
Serves an interactive HTML5 single-page application with a dynamic SVG consistent hash ring rendering active virtual partitions and node coordinates.
