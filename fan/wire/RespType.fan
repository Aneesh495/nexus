**
** Supported RESP2 and RESP3 protocol data types.
**
enum class RespType
{
  simpleString,
  error,
  integer,
  bulkString,
  array,
  boolean,
  double,
  nullValue,
  map,
  set
}

**
** Immutable representation of a parsed RESP value.
**
const class RespValue
{
  const RespType type
  const Obj? val

  new make(RespType type, Obj? val)
  {
    this.type = type
    this.val = val
  }

  static RespValue simpleString(Str str)    { RespValue(RespType.simpleString, str) }
  static RespValue error(Str msg)           { RespValue(RespType.error, msg) }
  static RespValue integer(Int n)           { RespValue(RespType.integer, n) }
  static RespValue bulkString(Str? str)     { RespValue(RespType.bulkString, str) }
  static RespValue array(RespValue[] items) { RespValue(RespType.array, items) }
  static RespValue nil()                    { RespValue(RespType.nullValue, null) }
  static RespValue boolean(Bool b)          { RespValue(RespType.boolean, b) }
  static RespValue double(Float f)          { RespValue(RespType.double, f) }

  Bool isNull() { type == RespType.nullValue || (type == RespType.bulkString && val == null) }

  Str asStr()
  {
    if (val is Str) return (Str)val
    if (val == null) return ""
    return val.toStr
  }

  Int asInt()
  {
    if (val is Int) return (Int)val
    if (val is Str) return ((Str)val).toInt
    return 0
  }

  Float asFloat()
  {
    if (val is Float) return (Float)val
    if (val is Str) return ((Str)val).toFloat
    return 0.0f
  }

  Bool asBool()
  {
    if (val is Bool) return (Bool)val
    return false
  }

  RespValue[] asArray()
  {
    if (val is List) return (RespValue[])val
    return RespValue[,]
  }

  override Str toStr()
  {
    return "RespValue($type, $val)"
  }

  override Bool equals(Obj? that)
  {
    other := that as RespValue
    if (other == null) return false
    return type == other.type && val == other.val
  }

  override Int hash()
  {
    return type.hash.xor(val?.hash ?: 0)
  }
}
