using concurrent
using inet

**
** Multi-protocol TCP network server accepting concurrent client connections.
** Automatically multiplexes Redis RESP2/RESP3 protocol commands and
** HTTP 1.1 REST / Prometheus metrics scraping on the same port.
**
class TcpServer
{
  private Int bindPort
  private RespCommandDispatcher dispatcher
  private HttpRouter httpRouter
  private AtomicBool running := AtomicBool(false)
  private TcpListener? listener
  private ActorPool pool := ActorPool()

  new make(
    Int bindPort := 6379,
    RespCommandDispatcher? dispatcher := null,
    HttpRouter? httpRouter := null)
  {
    this.bindPort = bindPort
    this.dispatcher = dispatcher ?: RespCommandDispatcher()
    PartitionStore store := PartitionStore(0, 50000, 50 * 1024 * 1024)
    this.httpRouter = httpRouter ?: HttpRouter(store, 1, 0)
  }

  ** Check whether server is actively accepting connections **
  Bool isRunning() { running.val }

  ** Get bound local port **
  Int localPort()
  {
    return listener?.localPort ?: bindPort
  }

  **
  ** Start listening on configured port in an asynchronous background actor.
  **
  Void start()
  {
    if (running.getAndSet(true)) return

    listener = TcpListener()
    listener.bind(null, bindPort == 0 ? null : bindPort)

    listenerRef := Unsafe(listener)
    dispRef := Unsafe(dispatcher)
    routeRef := Unsafe(httpRouter)
    runRef := running
    p := pool

    // Launch connection acceptance actor
    Actor(p) |->Obj?|
    {
      runAcceptLoop(p, listenerRef, runRef, dispRef, routeRef)
      return null
    }.send(null)
  }

  internal static Void runAcceptLoop(
    ActorPool pool,
    Unsafe listenerRef,
    AtomicBool running,
    Unsafe dispRef,
    Unsafe routeRef)
  {
    TcpListener l := listenerRef.val
    while (running.val && !l.isClosed)
    {
      try
      {
        socket := l.accept
        socketRef := Unsafe(socket)
        Actor(pool) |->Obj?|
        {
          handleClient(socketRef, dispRef, routeRef, running)
          return null
        }.send(null)
      }
      catch (Err e)
      {
        if (!running.val) break
      }
    }
  }

  **
  ** Process incoming stream on a client socket.
  **
  internal static Void handleClient(
    Unsafe socketRef,
    Unsafe dispRef,
    Unsafe routeRef,
    AtomicBool running)
  {
    TcpSocket socket := socketRef.val
    RespCommandDispatcher dispatcher := dispRef.val
    HttpRouter httpRouter := routeRef.val

    try
    {
      inStream := socket.in
      outStream := socket.out
      readBuf := ByteBuf(4096)

      while (running.val && !socket.isClosed)
      {
        byteVal := inStream.read
        if (byteVal == -1) break // EOF

        readBuf.writeByte(byteVal)

        // Protocol sniffing: check if request is HTTP
        if (readBuf.readableBytes >= 4)
        {
          b0 := readBuf.peekByte(0)
          b1 := readBuf.peekByte(1)
          b2 := readBuf.peekByte(2)
          b3 := readBuf.peekByte(3)

          isHttp := (b0 == 'G' && b1 == 'E' && b2 == 'T' && b3 == ' ') ||
                    (b0 == 'P' && b1 == 'O' && b2 == 'S' && b3 == 'T') ||
                    (b0 == 'P' && b1 == 'U' && b2 == 'T' && b3 == ' ') ||
                    (b0 == 'D' && b1 == 'E' && b2 == 'L' && b3 == 'E')

          if (isHttp)
          {
            handleHttp(readBuf, inStream, outStream, httpRouter)
            socket.close
            return
          }
        }

        // RESP parsing
        respVal := RespParser.parse(readBuf)
        if (respVal != null)
        {
          // Dispatch command
          response := dispatcher.dispatch(respVal)

          // Format and write response to client
          respBuf := ByteBuf(1024)
          RespFormatter.writeValue(respBuf, response)

          respBytes := respBuf.readBytes(respBuf.readableBytes)
          for (i := 0; i < respBytes.size; ++i)
            outStream.write(respBytes[i])
          outStream.flush

          readBuf.discardReadBytes
        }
      }
    }
    catch (Err e)
    {
      // Connection closed or reset by peer
    }
    finally
    {
      try { socket.close } catch (Err ignore) {}
    }
  }

  private static Void handleHttp(ByteBuf initialBuf, InStream inStream, OutStream outStream, HttpRouter httpRouter)
  {
    // Read remainder of HTTP header until \r\n\r\n
    rawHeader := initialBuf.readUtf8Bytes(initialBuf.readableBytes)
    headerBuf := StrBuf().add(rawHeader)

    while (!headerBuf.toStr.contains("\r\n\r\n"))
    {
      b := inStream.read
      if (b == -1) break
      headerBuf.addChar(b)
    }

    req := HttpRequest.parse(headerBuf.toStr)
    if (req != null)
    {
      res := httpRouter.handle(req)
      formatted := res.format
      for (i := 0; i < formatted.size; ++i)
        outStream.write(formatted[i])
      outStream.flush
    }
  }

  ** Stop listening and terminate connection thread pool **
  Void stop()
  {
    running.val = false
    try { listener?.close } catch (Err ignore) {}
    pool.stop
    pool.join(5sec)
  }
}
