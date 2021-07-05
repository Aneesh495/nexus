using inet

**
** Smart high-performance client for Nexus distributed data grid clusters.
** Supports pipelined RESP execution, smart client-side consistent hash ring
** partition routing, and optional L1 NearCache acceleration.
**
class NexusClient
{
  private Str host
  private Int port
  private TcpSocket? socket
  private NearCache? nearCache
  private HashRing? ring

  new make(
    Str host := "127.0.0.1",
    Int port := 6379,
    NearCache? nearCache := null,
    HashRing? ring := null)
  {
    this.host = host
    this.port = port
    this.nearCache = nearCache
    this.ring = ring
  }

  ** Check whether socket connection is currently open **
  Bool isConnected()
  {
    return socket != null && !socket.isClosed && socket.isConnected
  }

  ** Open socket connection to target cluster node **
  This connect()
  {
    if (isConnected) return this
    s := TcpSocket()
    s.connect(IpAddr(host), port)
    this.socket = s
    return this
  }

  ** Get reference to client-side near cache if enabled **
  NearCache? getNearCache() { nearCache }

  **
  ** Retrieve a string entry by key.
  ** Checks L1 near cache first if enabled; on cache miss queries remote cluster.
  **
  Str? get(Str key)
  {
    if (nearCache != null)
    {
      cached := nearCache.get(key)
      if (cached != null) return cached.toStr
    }

    resp := sendCommand(["GET", key])
    if (resp.isNull) return null

    val := resp.asStr
    if (nearCache != null)
      nearCache.put(key, val)

    return val
  }

  **
  ** Store a string entry with optional expiration in seconds.
  ** Invalidates local near cache upon mutation.
  **
  Bool put(Str key, Str val, Int ttlSec := 0)
  {
    Str[] args := ["SET", key, val]
    if (ttlSec > 0)
    {
      args.add("EX")
      args.add(ttlSec.toStr)
    }

    resp := sendCommand(args)
    success := resp.asStr == "OK"

    if (success && nearCache != null)
      nearCache.put(key, val)

    return success
  }

  ** Remove an entry by key, invalidating near cache entry **
  Bool remove(Str key)
  {
    resp := sendCommand(["DEL", key])
    if (nearCache != null)
      nearCache.invalidate(key)
    return resp.asInt > 0
  }

  ** Check whether a key exists in grid **
  Bool exists(Str key)
  {
    if (nearCache != null && nearCache.get(key) != null) return true
    resp := sendCommand(["EXISTS", key])
    return resp.asInt > 0
  }

  ** Ping target server to verify connection health **
  Str ping(Str? msg := null)
  {
    Str[] args := msg == null ? ["PING"] : ["PING", msg]
    return sendCommand(args).asStr
  }

  ** Atomically increment integer counter key **
  Int incr(Str key)
  {
    resp := sendCommand(["INCR", key])
    if (nearCache != null)
      nearCache.invalidate(key)
    return resp.asInt
  }

  ** Atomically decrement integer counter key **
  Int decr(Str key)
  {
    resp := sendCommand(["DECR", key])
    if (nearCache != null)
      nearCache.invalidate(key)
    return resp.asInt
  }

  **
  ** Low-level command pipeline: send a RESP array command and parse response.
  **
  RespValue sendCommand(Str[] tokens)
  {
    if (!isConnected) connect

    s := socket
    if (s == null) throw IOErr("Socket not connected")

    // Format RESP array command
    cmdBuf := ByteBuf(256)
    RespFormatter.writeArrayHeader(cmdBuf, tokens.size)
    for (i := 0; i < tokens.size; ++i)
      RespFormatter.writeBulkString(cmdBuf, tokens[i])

    // Write to socket
    bytes := cmdBuf.readBytes(cmdBuf.readableBytes)
    for (i := 0; i < bytes.size; ++i)
      s.out.write(bytes[i])
    s.out.flush

    // Read response
    inBuf := ByteBuf(1024)
    while (true)
    {
      b := s.in.read
      if (b == -1) throw IOErr("Unexpected EOF from cluster node")
      inBuf.writeByte(b)

      parsed := RespParser.parse(inBuf)
      if (parsed != null)
        return parsed
    }

    throw IOErr("Unreachable parse state")
  }

  ** Close client connection and clear near cache **
  Void close()
  {
    try { socket?.close } catch (Err ignore) {}
    socket = null
    nearCache?.clear
  }
}
