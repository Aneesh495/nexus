**
** Generates embedded HTML5 and responsive SVG cluster topology visualization
** for browser-based cluster monitoring and telemetry inspection.
**
class DashboardAssets
{
  **
  ** Render self-contained HTML5 dashboard page with embedded SVG topology graph.
  **
  static Str renderDashboardHtml(Str clusterName := "nexus-cluster-prod", Int nodes := 3, Int partitions := 16384)
  {
    svgContent := renderSvgTopology(nodes)

    return "<!DOCTYPE html>\n" +
           "<html lang=\"en\">\n" +
           "<head>\n" +
           "  <meta charset=\"UTF-8\">\n" +
           "  <title>Nexus Distributed Grid Console | " + clusterName + "</title>\n" +
           "  <style>\n" +
           "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 24px; }\n" +
           "    .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #1e293b; padding-bottom: 16px; margin-bottom: 24px; }\n" +
           "    .title { font-size: 24px; font-weight: 700; color: #38bdf8; }\n" +
           "    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; margin-bottom: 24px; }\n" +
           "    .card { background: #1e293b; border-radius: 8px; padding: 16px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.3); border: 1px solid #334155; }\n" +
           "    .card-title { font-size: 13px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px; }\n" +
           "    .card-value { font-size: 28px; font-weight: 700; color: #f1f5f9; }\n" +
           "    .viz-container { background: #1e293b; border-radius: 8px; padding: 24px; text-align: center; border: 1px solid #334155; }\n" +
           "  </style>\n" +
           "</head>\n" +
           "<body>\n" +
           "  <div class=\"header\">\n" +
           "    <div class=\"title\">Nexus Grid Console: " + clusterName + "</div>\n" +
           "    <div>Cluster Status: <span style=\"color: #4ade80; font-weight: bold;\">HEALTHY</span></div>\n" +
           "  </div>\n" +
           "  <div class=\"grid\">\n" +
           "    <div class=\"card\"><div class=\"card-title\">Active Cluster Nodes</div><div class=\"card-value\">" + nodes.toStr + "</div></div>\n" +
           "    <div class=\"card\"><div class=\"card-title\">Virtual Partitions</div><div class=\"card-value\">" + partitions.toStr + "</div></div>\n" +
           "    <div class=\"card\"><div class=\"card-title\">Consensus Protocol</div><div class=\"card-value\">Multi-Raft</div></div>\n" +
           "    <div class=\"card\"><div class=\"card-title\">Wire Protocol</div><div class=\"card-value\">RESP3 / Binary</div></div>\n" +
           "  </div>\n" +
           "  <div class=\"viz-container\">\n" +
           "    <h3>Dynamic Consistent Hash Ring Topology</h3>\n" +
           svgContent + "\n" +
           "  </div>\n" +
           "</body>\n" +
           "</html>\n"
  }

  **
  ** Render an SVG topology diagram showing nodes distributed around the hash ring.
  **
  static Str renderSvgTopology(Int nodeCount)
  {
    cx := 250
    cy := 250
    r := 180

    buf := StrBuf(1024)
    buf.add("<svg viewBox=\"0 0 500 500\" width=\"400\" height=\"400\" xmlns=\"http://www.w3.org/2000/svg\">\n")

    // Background circle representing consistent hash ring [0 .. 2^64-1]
    buf.add("  <circle cx=\"$cx\" cy=\"$cy\" r=\"$r\" fill=\"none\" stroke=\"#334155\" stroke-width=\"4\" stroke-dasharray=\"6,6\" />\n")

    // Render node circles around ring
    count := nodeCount.max(1)
    for (i := 0; i < count; ++i)
    {
      angle := (2.0f * Float.pi * i.toFloat) / count.toFloat
      nx := (cx.toFloat + r.toFloat * angle.cos).round.toInt
      ny := (cy.toFloat + r.toFloat * angle.sin).round.toInt

      nodeLabel := "Node-${i + 1}"
      buf.add("  <circle cx=\"$nx\" cy=\"$ny\" r=\"24\" fill=\"#0284c7\" stroke=\"#38bdf8\" stroke-width=\"3\" />\n")
      buf.add("  <text x=\"$nx\" y=\"${ny + 5}\" fill=\"#ffffff\" font-size=\"11\" font-weight=\"bold\" text-anchor=\"middle\">$nodeLabel</text>\n")
    }

    buf.add("</svg>")
    return buf.toStr
  }
}
