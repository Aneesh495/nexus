using concurrent
using inet

class TcpServerTest : Test
{
  Void testServerLifecycle()
  {
    server := TcpServer(0)
    verifyEq(server.isRunning, false)

    server.start
    verifyEq(server.isRunning, true)
    verifyTrue(server.localPort > 0)

    server.stop
    verifyEq(server.isRunning, false)
  }

  Void testRespPingOverSocket()
  {
    server := TcpServer(0)
    server.start
    port := server.localPort

    // Connect client socket
    client := TcpSocket()
    client.connect(IpAddr("127.0.0.1"), port)

    try
    {
      // Send RESP Ping command
      client.out.print("*1\r\n\$4\r\nPING\r\n").flush

      line := client.in.readLine
      verifyEq(line, "+PONG")
    }
    finally
    {
      client.close
      server.stop
    }
  }

  Void testRespSetGetOverSocket()
  {
    server := TcpServer(0)
    server.start
    port := server.localPort

    client := TcpSocket()
    client.connect(IpAddr("127.0.0.1"), port)

    try
    {
      // SET alpha omega
      client.out.print("*3\r\n\$3\r\nSET\r\n\$5\r\nalpha\r\n\$5\r\nomega\r\n").flush
      rSet := client.in.readLine
      verifyEq(rSet, "+OK")

      // GET alpha
      client.out.print("*2\r\n\$3\r\nGET\r\n\$5\r\nalpha\r\n").flush
      lenLine := client.in.readLine
      verifyEq(lenLine, "\$5")
      valLine := client.in.readLine
      verifyEq(valLine, "omega")
    }
    finally
    {
      client.close
      server.stop
    }
  }

  Void testHttpMetricsOverSocket()
  {
    server := TcpServer(0)
    server.start
    port := server.localPort

    client := TcpSocket()
    client.connect(IpAddr("127.0.0.1"), port)

    try
    {
      client.out.print("GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").flush

      statusLine := client.in.readLine
      verifyTrue(statusLine.contains("200 OK"))

      allContent := client.in.readAllStr
      verifyTrue(allContent.contains("nexus_cluster_nodes"))
    }
    finally
    {
      client.close
      server.stop
    }
  }
}
