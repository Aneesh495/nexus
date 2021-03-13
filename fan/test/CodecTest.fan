**
** Unit tests for Codec binary serializer.
**
class CodecTest : Test
{
  Void testPrimitivesRoundtrip()
  {
    buf := ByteBuf()

    Codec.encode(null, buf)
    Codec.encode(true, buf)
    Codec.encode(false, buf)
    Codec.encode(42, buf)
    Codec.encode(-123456789, buf)
    Codec.encode(3.14159f, buf)
    Codec.encode("Nexus Grid", buf)

    verifyEq(Codec.decode(buf), null)
    verifyEq(Codec.decode(buf), true)
    verifyEq(Codec.decode(buf), false)
    verifyEq(Codec.decode(buf), 42)
    verifyEq(Codec.decode(buf), -123456789)
    fVal := (Float)Codec.decode(buf)
    verify((fVal - 3.14159f).abs < 0.0001f)
    verifyEq(Codec.decode(buf), "Nexus Grid")
  }

  Void testCollectionsAndNestedMaps()
  {
    buf := ByteBuf()
    nested := [
      "cluster": "east-1",
      "nodes": [1, 2, 3],
      "active": true,
      "metadata": ["rack": "R42", "weight": 100]
    ]

    Codec.encode(nested, buf)
    decoded := (Map)Codec.decode(buf)

    verifyEq(decoded["cluster"], "east-1")
    verifyEq(decoded["active"], true)
    nodes := (List)decoded["nodes"]
    verifyEq(nodes.size, 3)
    verifyEq(nodes[0], 1)
    verifyEq(nodes[2], 3)

    meta := (Map)decoded["metadata"]
    verifyEq(meta["rack"], "R42")
    verifyEq(meta["weight"], 100)
  }

  Void testClocksRoundtrip()
  {
    buf := ByteBuf()
    hlc := HybridLogicalClock(1730553600000, 99)
    vc := VectorClock(["node-A": 10, "node-B": 25])

    Codec.encode(hlc, buf)
    Codec.encode(vc, buf)

    decodedHlc := (HybridLogicalClock)Codec.decode(buf)
    decodedVc := (VectorClock)Codec.decode(buf)

    verifyEq(decodedHlc.physical, hlc.physical)
    verifyEq(decodedHlc.logical, hlc.logical)
    verifyEq(decodedVc.get("node-A"), 10)
    verifyEq(decodedVc.get("node-B"), 25)
  }
}
