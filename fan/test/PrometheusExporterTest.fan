class PrometheusExporterTest : Test
{
  Void testPrometheusFormatting()
  {
    metrics := PrometheusExporter.renderMetrics(5, 50000, 104857600, 250000, 3, 4096, 2)

    verifyTrue(metrics.contains("# HELP nexus_cluster_nodes Total active nodes registered in cluster topology"))
    verifyTrue(metrics.contains("# TYPE nexus_cluster_nodes gauge"))
    verifyTrue(metrics.contains("nexus_cluster_nodes 5"))

    verifyTrue(metrics.contains("# HELP nexus_keyspace_entries Total entries stored across memory partitions"))
    verifyTrue(metrics.contains("nexus_keyspace_entries 50000"))

    verifyTrue(metrics.contains("nexus_memory_bytes 104857600"))

    verifyTrue(metrics.contains("# TYPE nexus_operations_total counter"))
    verifyTrue(metrics.contains("nexus_operations_total 250000"))

    verifyTrue(metrics.contains("nexus_raft_term 3"))
    verifyTrue(metrics.contains("nexus_raft_commit_index 4096"))
    verifyTrue(metrics.contains("nexus_active_transactions 2"))
  }

  Void testHttpRequestParsing()
  {
    rawReq := "GET /api/v1/keys/user:99 HTTP/1.1\r\n" +
              "Host: localhost:8080\r\n" +
              "User-Agent: curl/7.88.1\r\n" +
              "Accept: */*\r\n\r\n"

    req := HttpRequest.parse(rawReq)
    verifyNotNull(req)
    verifyEq(req.method, "GET")
    verifyEq(req.path, "/api/v1/keys/user:99")
    verifyEq(req.headers["host"], "localhost:8080")
    verifyEq(req.body, "")

    // PUT with body
    rawPut := "PUT /api/v1/keys/config HTTP/1.1\r\n" +
              "Content-Length: 13\r\n\r\n" +
              "active_mode=1"

    putReq := HttpRequest.parse(rawPut)
    verifyNotNull(putReq)
    verifyEq(putReq.method, "PUT")
    verifyEq(putReq.path, "/api/v1/keys/config")
    verifyEq(putReq.body, "active_mode=1")
  }

  Void testHttpResponseFormatting()
  {
    resp := HttpResponse.ok("{\"status\":\"ok\"}")
    formatted := resp.format

    verifyTrue(formatted.startsWith("HTTP/1.1 200 OK\r\n"))
    verifyTrue(formatted.contains("content-type: application/json\r\n"))
    verifyTrue(formatted.contains("server: Nexus-Grid/2.0.0\r\n"))
    verifyTrue(formatted.contains("{\"status\":\"ok\"}"))

    resp404 := HttpResponse.notFound("Resource missing")
    verifyTrue(resp404.format.startsWith("HTTP/1.1 404 Not Found\r\n"))
  }

  Void testHttpRouterMetricsAndHealthz()
  {
    store := PartitionStore(0, 1000, 10 * 1024 * 1024)
    store.put("cache:1", "data")

    router := HttpRouter(store, 3, 500)

    // /metrics
    reqMetrics := HttpRequest("GET", "/metrics")
    resMetrics := router.handle(reqMetrics)
    verifyEq(resMetrics.statusCode, 200)
    verifyEq(resMetrics.headers["content-type"], "text/plain; version=0.0.4")
    verifyTrue(resMetrics.body.contains("nexus_cluster_nodes 3"))
    verifyTrue(resMetrics.body.contains("nexus_keyspace_entries 1"))

    // /healthz
    reqHealth := HttpRequest("GET", "/healthz")
    resHealth := router.handle(reqHealth)
    verifyEq(resHealth.statusCode, 200)
    verifyTrue(resHealth.body.contains("\"status\":\"UP\""))

    // /api/v1/topology
    reqTopo := HttpRequest("GET", "/api/v1/topology")
    resTopo := router.handle(reqTopo)
    verifyEq(resTopo.statusCode, 200)
    verifyTrue(resTopo.body.contains("\"status\":\"healthy\""))
  }

  Void testHttpRouterRestCrud()
  {
    store := PartitionStore(0, 1000, 10 * 1024 * 1024)
    router := HttpRouter(store, 1, 10)

    // PUT /api/v1/keys/session:abc
    putReq := HttpRequest("PUT", "/api/v1/keys/session:abc", Str:Str[:], "authenticated=true")
    putRes := router.handle(putReq)
    verifyEq(putRes.statusCode, 200)
    verifyTrue(putRes.body.contains("\"status\":\"stored\""))

    // GET /api/v1/keys/session:abc
    getReq := HttpRequest("GET", "/api/v1/keys/session:abc")
    getRes := router.handle(getReq)
    verifyEq(getRes.statusCode, 200)
    verifyTrue(getRes.body.contains("authenticated=true"))

    // DELETE /api/v1/keys/session:abc
    delReq := HttpRequest("DELETE", "/api/v1/keys/session:abc")
    delRes := router.handle(delReq)
    verifyEq(delRes.statusCode, 200)
    verifyTrue(delRes.body.contains("\"status\":\"deleted\""))

    // GET after DELETE -> 404
    getRes2 := router.handle(getReq)
    verifyEq(getRes2.statusCode, 404)
  }
}
