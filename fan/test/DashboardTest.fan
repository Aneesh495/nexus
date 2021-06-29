class DashboardTest : Test
{
  Void testHtmlGeneration()
  {
    html := DashboardAssets.renderDashboardHtml("eu-west-cluster", 4, 16384)

    verifyTrue(html.contains("<!DOCTYPE html>"))
    verifyTrue(html.contains("Nexus Distributed Grid Console | eu-west-cluster"))
    verifyTrue(html.contains("Active Cluster Nodes</div><div class=\"card-value\">4</div>"))
    verifyTrue(html.contains("Virtual Partitions</div><div class=\"card-value\">16384</div>"))
    verifyTrue(html.contains("Multi-Raft"))
    verifyTrue(html.contains("RESP3 / Binary"))
  }

  Void testSvgTopologyRendering()
  {
    svg := DashboardAssets.renderSvgTopology(3)

    verifyTrue(svg.startsWith("<svg viewBox=\"0 0 500 500\""))
    verifyTrue(svg.contains("stroke-dasharray=\"6,6\""))
    verifyTrue(svg.contains("Node-1"))
    verifyTrue(svg.contains("Node-2"))
    verifyTrue(svg.contains("Node-3"))
    verifyTrue(svg.endsWith("</svg>"))
  }

  Void testHttpRoutingToDashboard()
  {
    store := PartitionStore(0, 1000, 10 * 1024 * 1024)
    router := HttpRouter(store, 3, 100)

    req1 := HttpRequest("GET", "/")
    res1 := router.handle(req1)
    verifyEq(res1.statusCode, 200)
    verifyEq(res1.headers["content-type"], "text/html; charset=utf-8")
    verifyTrue(res1.body.contains("Nexus Distributed Grid Console"))

    req2 := HttpRequest("GET", "/dashboard")
    res2 := router.handle(req2)
    verifyEq(res2.statusCode, 200)
    verifyTrue(res2.body.contains("Dynamic Consistent Hash Ring Topology"))
  }
}
