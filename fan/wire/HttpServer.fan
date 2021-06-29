**
** HTTP request representation containing HTTP method, path, headers, and body.
**
class HttpRequest
{
  Str method
  Str path
  Str:Str headers
  Str body

  new make(Str method, Str path, Str:Str headers := Str:Str[:], Str body := "")
  {
    this.method = method.upper
    this.path = path
    this.headers = headers
    this.body = body
  }

  ** Parse raw HTTP request text into an HttpRequest object **
  static HttpRequest? parse(Str raw)
  {
    lines := raw.splitLines
    if (lines.isEmpty) return null

    firstLine := lines[0].split(' ')
    if (firstLine.size < 2) return null

    m := firstLine[0]
    p := firstLine[1]

    headers := Str:Str[:]
    idx := 1
    while (idx < lines.size)
    {
      line := lines[idx].trim
      if (line.isEmpty)
      {
        idx++
        break
      }
      colon := line.index(":")
      if (colon != null)
      {
        k := line[0..<colon].trim.lower
        v := line[colon + 1..-1].trim
        headers[k] = v
      }
      idx++
    }

    bodyBuf := StrBuf()
    while (idx < lines.size)
    {
      bodyBuf.add(lines[idx]).add("\n")
      idx++
    }

    return HttpRequest(m, p, headers, bodyBuf.toStr.trim)
  }
}

**
** HTTP response representation with status code, headers, and payload serialization.
**
class HttpResponse
{
  Int statusCode
  Str statusMsg
  Str:Str headers
  Str body

  new make(Int statusCode, Str statusMsg, Str body := "", Str contentType := "application/json")
  {
    this.statusCode = statusCode
    this.statusMsg = statusMsg
    this.headers = Str:Str[:]
    this.headers["content-type"] = contentType
    this.headers["content-length"] = body.toBuf.size.toStr
    this.headers["server"] = "Nexus-Grid/2.0.0"
    this.headers["connection"] = "close"
    this.body = body
  }

  static HttpResponse ok(Str body, Str contentType := "application/json")
  {
    return HttpResponse(200, "OK", body, contentType)
  }

  static HttpResponse notFound(Str msg := "Not Found")
  {
    return HttpResponse(404, "Not Found", "{\"error\":\"${msg}\"}")
  }

  static HttpResponse badRequest(Str msg := "Bad Request")
  {
    return HttpResponse(400, "Bad Request", "{\"error\":\"${msg}\"}")
  }

  static HttpResponse serverError(Str msg := "Internal Error")
  {
    return HttpResponse(500, "Internal Server Error", "{\"error\":\"${msg}\"}")
  }

  ** Format as raw HTTP 1.1 response wire text **
  Str format()
  {
    buf := StrBuf(256 + body.size)
    buf.add("HTTP/1.1 ").add(statusCode.toStr).add(" ").add(statusMsg).add("\r\n")
    headers.each |v, k|
    {
      buf.add(k).add(": ").add(v).add("\r\n")
    }
    buf.add("\r\n")
    buf.add(body)
    return buf.toStr
  }
}

**
** REST API and observability HTTP router.
**
class HttpRouter
{
  private PartitionStore store
  private Int clusterNodes
  private Int totalOps

  new make(PartitionStore store, Int clusterNodes := 1, Int totalOps := 0)
  {
    this.store = store
    this.clusterNodes = clusterNodes
    this.totalOps = totalOps
  }

  ** Route an incoming request to appropriate endpoint handler **
  HttpResponse handle(HttpRequest req)
  {
    path := req.path

    if (path == "/" || path == "/dashboard")
    {
      html := DashboardAssets.renderDashboardHtml("nexus-grid-cluster", clusterNodes)
      return HttpResponse.ok(html, "text/html; charset=utf-8")
    }

    if (path == "/metrics")
    {
      metricsText := PrometheusExporter.renderMetrics(
        clusterNodes,
        store.size,
        store.memoryBytes,
        totalOps
      )
      return HttpResponse.ok(metricsText, "text/plain; version=0.0.4")
    }

    if (path == "/healthz")
    {
      json := "{\"status\":\"UP\",\"cluster_nodes\":$clusterNodes,\"keys\":${store.size}}"
      return HttpResponse.ok(json)
    }

    if (path == "/api/v1/topology")
    {
      json := "{\"status\":\"healthy\",\"nodes\":$clusterNodes,\"partitions\":16384}"
      return HttpResponse.ok(json)
    }

    // Key-value REST endpoints: /api/v1/keys/{key}
    if (path.startsWith("/api/v1/keys/"))
    {
      key := path["/api/v1/keys/".size..-1]
      if (key.isEmpty) return HttpResponse.badRequest("Missing key identifier")

      if (req.method == "GET")
      {
        entry := store.get(key)
        if (entry == null) return HttpResponse.notFound("Key not found: $key")
        json := "{\"key\":\"${key}\",\"value\":\"${entry.val}\",\"version\":\"${entry.version}\"}"
        return HttpResponse.ok(json)
      }
      else if (req.method == "PUT" || req.method == "POST")
      {
        store.put(key, req.body)
        json := "{\"status\":\"stored\",\"key\":\"${key}\"}"
        return HttpResponse.ok(json)
      }
      else if (req.method == "DELETE")
      {
        removed := store.remove(key)
        if (removed == null) return HttpResponse.notFound("Key not found: $key")
        json := "{\"status\":\"deleted\",\"key\":\"${key}\"}"
        return HttpResponse.ok(json)
      }
    }

    return HttpResponse.notFound("No route found for path: $path")
  }
}
