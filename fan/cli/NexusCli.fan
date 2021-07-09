**
** Interactive command-line REPL for Nexus data grid clusters.
**
class NexusCli
{
  static Void main(Str[] args)
  {
    host := "127.0.0.1"
    port := 6379

    for (i := 0; i < args.size; ++i)
    {
      if ((args[i] == "-h" || args[i] == "--host") && i + 1 < args.size)
        host = args[i + 1]
      else if ((args[i] == "-p" || args[i] == "--port") && i + 1 < args.size)
        port = args[i + 1].toInt
    }

    echo("Nexus Interactive Console ($host:$port)")
    echo("Type 'help' for commands, 'quit' or 'exit' to terminate.")

    client := NexusClient(host, port)
    try
    {
      client.connect
      echo("Connected to $host:$port")
    }
    catch (Err e)
    {
      echo("Failed to connect to $host:$port: ${e.msg}")
      return
    }

    inStream := Env.cur.in

    while (true)
    {
      Env.cur.out.print("nexus> ").flush
      line := inStream.readLine
      if (line == null) break

      trimmed := line.trim
      if (trimmed.isEmpty) continue
      if (trimmed.lower == "quit" || trimmed.lower == "exit") break

      tokens := trimmed.split(' ')
      try
      {
        resp := client.sendCommand(tokens)
        echo(formatResponse(resp))
      }
      catch (Err e)
      {
        echo("(error) ${e.msg}")
      }
    }

    client.close
    echo("Disconnected.")
  }

  static Str formatResponse(RespValue resp)
  {
    switch (resp.type)
    {
      case RespType.simpleString:
        return resp.asStr
      case RespType.error:
        return "(error) ${resp.asStr}"
      case RespType.integer:
        return "(integer) ${resp.asInt}"
      case RespType.bulkString:
        if (resp.val == null) return "(nil)"
        return "\"${resp.asStr}\""
      case RespType.array:
        arr := resp.asArray
        if (arr.isEmpty) return "(empty array)"
        buf := StrBuf()
        for (i := 0; i < arr.size; ++i)
        {
          buf.add("${i + 1}) ").add(formatResponse(arr[i])).add("\n")
        }
        return buf.toStr.trim
      case RespType.nullValue:
        return "(nil)"
      case RespType.boolean:
        return resp.asBool ? "true" : "false"
      default:
        return resp.asStr
    }
  }
}
