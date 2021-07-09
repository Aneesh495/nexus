using concurrent

**
** Main server daemon entrypoint for launching a Nexus IMDG node.
**
class NexusServerMain
{
  static Void main(Str[] args)
  {
    port := 6379
    if (!args.isEmpty)
    {
      for (i := 0; i < args.size; ++i)
      {
        if ((args[i] == "-p" || args[i] == "--port") && i + 1 < args.size)
          port = args[i + 1].toInt
      }
    }

    echo("=================================================================")
    echo("   _   _  _______  __ _   _ ____  ")
    echo("  | \\ | || ____\\ \\/ /| | | / ___| ")
    echo("  |  \\| ||  _|   \\  / | | | \\___ \\ ")
    echo("  | |\\  || |___  /  \\ | |_| |___) |")
    echo("  |_| \\_||_____|/_/\\_\\ \\___/|____/ ")
    echo("  Distributed In-Memory Data Grid & Reactive State Fabric")
    echo("=================================================================")
    echo("[nexus] Starting node on port ${port}...")
    echo("[nexus] RESP3 protocol: redis://127.0.0.1:${port}")
    echo("[nexus] REST / Metrics: http://127.0.0.1:${port}/metrics")
    echo("[nexus] Web Dashboard:  http://127.0.0.1:${port}/")

    server := TcpServer(port)
    server.start
    echo("[nexus] Node online and ready for traffic.")

    // Keep running until interrupt
    while (server.isRunning)
    {
      Actor.sleep(1sec)
    }
  }
}
