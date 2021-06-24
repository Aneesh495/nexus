**
** Dispatches Redis-compatible RESP commands to underlying PartitionStore
** and distributed data structures. Supports key-value, hash, list, set,
** and cluster topology operations.
**
class RespCommandDispatcher
{
  private PartitionStore store
  private Str:Str:Str hashes := Str:Str:Str[:]
  private Str:Str[] lists := Str:Str[][:]
  private Str:Str:Bool sets := Str:Str:Bool[:]
  private Int totalOps := 0
  private Int startTimeMillis := DateTime.now.toJava

  new make(PartitionStore? store := null)
  {
    this.store = store ?: PartitionStore(0, 100000, 100 * 1024 * 1024)
  }

  ** Return total number of commands dispatched **
  Int opCount() { totalOps }

  **
  ** Dispatch an incoming parsed RESP command and return the formatted RespValue.
  **
  RespValue dispatch(RespValue command)
  {
    totalOps++
    args := command.asArray
    if (args.isEmpty)
      return RespValue.error("ERR empty command")

    cmd := args[0].asStr.upper

    switch (cmd)
    {
      // --- Connection & Server ---
      case "PING":
        if (args.size > 1) return RespValue.bulkString(args[1].asStr)
        return RespValue.simpleString("PONG")

      case "ECHO":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'echo' command")
        return RespValue.bulkString(args[1].asStr)

      case "DBSIZE":
        return RespValue.integer(store.size)

      case "FLUSHDB":
      case "FLUSHALL":
        store.clear
        hashes.clear
        lists.clear
        sets.clear
        return RespValue.simpleString("OK")

      case "INFO":
        uptimeSec := (DateTime.now.toJava - startTimeMillis) / 1000
        infoStr := "# Server\r\n" +
                   "nexus_version:2.0.0\r\n" +
                   "uptime_in_seconds:$uptimeSec\r\n" +
                   "# Stats\r\n" +
                   "total_commands_processed:$totalOps\r\n" +
                   "# Keyspace\r\n" +
                   "db0:keys=${store.size},expires=0\r\n"
        return RespValue.bulkString(infoStr)

      // --- Strings & Keys ---
      case "GET":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'get' command")
        entry := store.get(args[1].asStr)
        if (entry == null) return RespValue.nil
        return RespValue.bulkString(entry.val.toStr)

      case "SET":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'set' command")
        key := args[1].asStr
        val := args[2].asStr
        ttlMillis := 0

        // Parse optional EX seconds or PX millis
        if (args.size >= 5)
        {
          opt := args[3].asStr.upper
          if (opt == "EX")
            ttlMillis = args[4].asStr.toInt * 1000
          else if (opt == "PX")
            ttlMillis = args[4].asStr.toInt
        }

        store.put(key, val, ttlMillis)
        return RespValue.simpleString("OK")

      case "SETNX":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'setnx' command")
        key := args[1].asStr
        val := args[2].asStr
        entry := store.putIfAbsent(key, val)
        return RespValue.integer(entry != null ? 1 : 0)

      case "MGET":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'mget' command")
        RespValue[] items := RespValue[,]
        for (i := 1; i < args.size; ++i)
        {
          entry := store.get(args[i].asStr)
          items.add(entry == null ? RespValue.nil : RespValue.bulkString(entry.val.toStr))
        }
        return RespValue.array(items)

      case "MSET":
        if (args.size < 3 || (args.size - 1) % 2 != 0)
          return RespValue.error("ERR wrong number of arguments for 'mset' command")
        for (i := 1; i < args.size; i += 2)
        {
          store.put(args[i].asStr, args[i + 1].asStr)
        }
        return RespValue.simpleString("OK")

      case "DEL":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'del' command")
        deleted := 0
        for (i := 1; i < args.size; ++i)
        {
          k := args[i].asStr
          if (store.remove(k) != null) deleted++
          if (hashes.remove(k) != null) deleted++
          if (lists.remove(k) != null) deleted++
          if (sets.remove(k) != null) deleted++
        }
        return RespValue.integer(deleted)

      case "EXISTS":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'exists' command")
        count := 0
        for (i := 1; i < args.size; ++i)
        {
          k := args[i].asStr
          if (store.containsKey(k) || hashes.containsKey(k) || lists.containsKey(k) || sets.containsKey(k))
            count++
        }
        return RespValue.integer(count)

      case "EXPIRE":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'expire' command")
        key := args[1].asStr
        sec := args[2].asStr.toInt
        entry := store.get(key)
        if (entry == null) return RespValue.integer(0)
        store.put(key, entry.val, sec * 1000)
        return RespValue.integer(1)

      case "TTL":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'ttl' command")
        entry := store.get(args[1].asStr)
        if (entry == null) return RespValue.integer(-2) // Not found
        if (entry.expireTime <= 0) return RespValue.integer(-1) // No expiry
        remainingSec := (entry.expireTime - DateTime.now.toJava) / 1000
        return RespValue.integer(remainingSec.max(0))

      case "INCR":
        return applyDelta(args, 1)

      case "DECR":
        return applyDelta(args, -1)

      case "INCRBY":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'incrby' command")
        return applyDelta(args, args[2].asStr.toInt)

      case "DECRBY":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'decrby' command")
        return applyDelta(args, -args[2].asStr.toInt)

      // --- Hashes ---
      case "HSET":
        if (args.size < 4) return RespValue.error("ERR wrong number of arguments for 'hset' command")
        key := args[1].asStr
        field := args[2].asStr
        val := args[3].asStr
        if (!hashes.containsKey(key)) hashes[key] = Str:Str[:]
        isNew := !hashes[key].containsKey(field)
        hashes[key][field] = val
        return RespValue.integer(isNew ? 1 : 0)

      case "HGET":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'hget' command")
        key := args[1].asStr
        field := args[2].asStr
        sub := hashes[key]
        if (sub == null || !sub.containsKey(field)) return RespValue.nil
        return RespValue.bulkString(sub[field])

      case "HDEL":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'hdel' command")
        key := args[1].asStr
        field := args[2].asStr
        sub := hashes[key]
        if (sub == null) return RespValue.integer(0)
        removed := sub.remove(field) != null
        return RespValue.integer(removed ? 1 : 0)

      case "HLEN":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'hlen' command")
        sub := hashes[args[1].asStr]
        return RespValue.integer(sub?.size ?: 0)

      case "HGETALL":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'hgetall' command")
        sub := hashes[args[1].asStr]
        RespValue[] items := RespValue[,]
        if (sub != null)
        {
          sub.each |v, f|
          {
            items.add(RespValue.bulkString(f))
            items.add(RespValue.bulkString(v))
          }
        }
        return RespValue.array(items)

      // --- Lists ---
      case "LPUSH":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'lpush' command")
        key := args[1].asStr
        if (!lists.containsKey(key)) lists[key] = Str[,]
        targetList := lists[key]
        for (i := 2; i < args.size; ++i)
          targetList.insert(0, args[i].asStr)
        return RespValue.integer(targetList.size)

      case "RPUSH":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'rpush' command")
        key := args[1].asStr
        if (!lists.containsKey(key)) lists[key] = Str[,]
        targetList := lists[key]
        for (i := 2; i < args.size; ++i)
          targetList.add(args[i].asStr)
        return RespValue.integer(targetList.size)

      case "LPOP":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'lpop' command")
        targetList := lists[args[1].asStr]
        if (targetList == null || targetList.isEmpty) return RespValue.nil
        popped := targetList.removeAt(0)
        return RespValue.bulkString(popped)

      case "RPOP":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'rpop' command")
        targetList := lists[args[1].asStr]
        if (targetList == null || targetList.isEmpty) return RespValue.nil
        popped := targetList.pop
        return RespValue.bulkString(popped)

      case "LLEN":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'llen' command")
        targetList := lists[args[1].asStr]
        return RespValue.integer(targetList?.size ?: 0)

      // --- Sets ---
      case "SADD":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'sadd' command")
        key := args[1].asStr
        if (!sets.containsKey(key)) sets[key] = Str:Bool[:]
        setMap := sets[key]
        added := 0
        for (i := 2; i < args.size; ++i)
        {
          m := args[i].asStr
          if (!setMap.containsKey(m))
          {
            setMap[m] = true
            added++
          }
        }
        return RespValue.integer(added)

      case "SMEMBERS":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'smembers' command")
        setMap := sets[args[1].asStr]
        RespValue[] items := RespValue[,]
        if (setMap != null)
        {
          setMap.keys.each |m| { items.add(RespValue.bulkString(m)) }
        }
        return RespValue.array(items)

      case "SISMEMBER":
        if (args.size < 3) return RespValue.error("ERR wrong number of arguments for 'sismember' command")
        setMap := sets[args[1].asStr]
        isMember := setMap != null && setMap.containsKey(args[2].asStr)
        return RespValue.integer(isMember ? 1 : 0)

      case "SCARD":
        if (args.size < 2) return RespValue.error("ERR wrong number of arguments for 'scard' command")
        setMap := sets[args[1].asStr]
        return RespValue.integer(setMap?.size ?: 0)

      // --- Cluster ---
      case "CLUSTER":
        subCmd := args.size > 1 ? args[1].asStr.upper : ""
        if (subCmd == "NODES")
        {
          clusterNodes := "07c37dfeb235204a 127.0.0.1:6379@16379 myself,master - 0 0 1 connected 0-16383\r\n"
          return RespValue.bulkString(clusterNodes)
        }
        else if (subCmd == "INFO")
        {
          clusterInfo := "cluster_state:ok\r\n" +
                         "cluster_slots_assigned:16384\r\n" +
                         "cluster_slots_ok:16384\r\n" +
                         "cluster_known_nodes:1\r\n" +
                         "cluster_size:1\r\n"
          return RespValue.bulkString(clusterInfo)
        }
        return RespValue.error("ERR unknown cluster subcommand '$subCmd'")

      default:
        return RespValue.error("ERR unknown command '$cmd'")
    }
  }

  private RespValue applyDelta(RespValue[] args, Int delta)
  {
    if (args.size < 2) return RespValue.error("ERR wrong number of arguments for increment/decrement")
    key := args[1].asStr
    entry := store.get(key)
    currentVal := 0
    if (entry != null)
    {
      try
      {
        currentVal = entry.val.toStr.toInt
      }
      catch (Err e)
      {
        return RespValue.error("ERR value is not an integer or out of range")
      }
    }
    newVal := currentVal + delta
    store.put(key, newVal.toStr)
    return RespValue.integer(newVal)
  }
}
