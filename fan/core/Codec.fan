**
** Codec: High-speed compact binary serializer for typed distributed state objects.
**
** Type Tag Wire Format:
** 0x00: Null
** 0x01: Boolean False
** 0x02: Boolean True
** 0x03: Signed Int (ZigZag encoded)
** 0x04: Float 64-bit IEEE 754
** 0x05: UTF-8 String (length-prefixed)
** 0x06: Binary Byte Array
** 0x07: Generic List
** 0x08: String-to-Object Map
** 0x09: HybridLogicalClock
** 0x0A: VectorClock
**
class Codec
{
  static const Int tagNull       := 0x00
  static const Int tagBoolFalse  := 0x01
  static const Int tagBoolTrue   := 0x02
  static const Int tagInt        := 0x03
  static const Int tagFloat      := 0x04
  static const Int tagStr        := 0x05
  static const Int tagBytes      := 0x06
  static const Int tagList       := 0x07
  static const Int tagMap        := 0x08
  static const Int tagHlc        := 0x09
  static const Int tagVectorClk  := 0x0A

  **
  ** Encode any supported value into the destination ByteBuf.
  **
  static Void encode(Obj? val, ByteBuf dst)
  {
    if (val == null)
    {
      dst.writeByte(tagNull)
      return
    }

    if (val is Bool)
    {
      dst.writeByte((Bool)val ? tagBoolTrue : tagBoolFalse)
      return
    }

    if (val is Int)
    {
      dst.writeByte(tagInt)
      dst.writeZigZag((Int)val)
      return
    }

    if (val is Float)
    {
      dst.writeByte(tagFloat)
      dst.writeF8((Float)val)
      return
    }

    if (val is Str)
    {
      dst.writeByte(tagStr)
      dst.writeUtf8((Str)val)
      return
    }

    if (val is ByteBuf)
    {
      bb := (ByteBuf)val
      dst.writeByte(tagBytes)
      dst.writeVarInt(bb.readableBytes)
      dst.writeBytes(bb.readBytes(bb.readableBytes))
      return
    }

    if (val is List)
    {
      list := (List)val
      dst.writeByte(tagList)
      dst.writeVarInt(list.size)
      for (i := 0; i < list.size; ++i)
      {
        encode(list[i], dst)
      }
      return
    }

    if (val is Map)
    {
      map := (Map)val
      dst.writeByte(tagMap)
      dst.writeVarInt(map.size)
      map.each |v, k|
      {
        dst.writeUtf8(k.toStr)
        encode(v, dst)
      }
      return
    }

    if (val is HybridLogicalClock)
    {
      hlc := (HybridLogicalClock)val
      dst.writeByte(tagHlc)
      dst.writeVarInt(hlc.physical)
      dst.writeVarInt(hlc.logical)
      return
    }

    if (val is VectorClock)
    {
      vc := (VectorClock)val
      dst.writeByte(tagVectorClk)
      dst.writeVarInt(vc.versions.size)
      vc.versions.each |version, node|
      {
        dst.writeUtf8(node)
        dst.writeVarInt(version)
      }
      return
    }

    // Fallback: encode as string representation
    dst.writeByte(tagStr)
    dst.writeUtf8(val.toStr)
  }

  **
  ** Decode next value from source ByteBuf.
  **
  static Obj? decode(ByteBuf src)
  {
    if (src.readableBytes == 0) return null
    tag := src.readByte

    switch (tag)
    {
      case tagNull:
        return null

      case tagBoolFalse:
        return false

      case tagBoolTrue:
        return true

      case tagInt:
        return src.readZigZag

      case tagFloat:
        return src.readF8

      case tagStr:
        return src.readUtf8

      case tagBytes:
        len := src.readVarInt
        return src.readBytes(len)

      case tagList:
        size := src.readVarInt
        out := Obj?[,]
        out.capacity = size
        for (i := 0; i < size; ++i)
        {
          out.add(decode(src))
        }
        return out

      case tagMap:
        size := src.readVarInt
        out := Str:Obj?[:]
        for (i := 0; i < size; ++i)
        {
          k := src.readUtf8
          v := decode(src)
          out[k] = v
        }
        return out

      case tagHlc:
        p := src.readVarInt
        l := src.readVarInt
        return HybridLogicalClock(p, l)

      case tagVectorClk:
        size := src.readVarInt
        m := Str:Int[:]
        for (i := 0; i < size; ++i)
        {
          node := src.readUtf8
          ver  := src.readVarInt
          m[node] = ver
        }
        return VectorClock(m)

      default:
        throw IOErr("Unknown codec tag: 0x" + tag.toHex)
    }
  }
}
