**
** NodeId: Immutable network identifier and endpoint descriptor for a cluster node.
**
const class NodeId
{
  const Str id
  const Str host
  const Int port
  const Int httpPort
  const Str zone
  const Int generation

  **
  ** Create new NodeId descriptor.
  **
  new make(
    Str id,
    Str host := "127.0.0.1",
    Int port := 8000,
    Int httpPort := 8080,
    Str zone := "default",
    Int generation := DateTime.now.toJava)
  {
    this.id         = id
    this.host       = host
    this.port       = port
    this.httpPort   = httpPort
    this.zone       = zone
    this.generation = generation
  }

  **
  ** Encode to compact URI address string: "host:port:httpPort#generation@zone"
  **
  Str toAddressStr()
  {
    return "$host:$port:$httpPort#$generation@$zone"
  }

  **
  ** Parse from address string.
  **
  static NodeId fromAddressStr(Str id, Str addr)
  {
    parts := addr.split('@')
    zone := parts.size > 1 ? parts[1] : "default"
    hostPortGen := parts[0].split('#')
    gen := hostPortGen.size > 1 ? hostPortGen[1].toInt : 0
    tokens := hostPortGen[0].split(':')
    h := tokens[0]
    p := tokens.size > 1 ? tokens[1].toInt : 8000
    hp := tokens.size > 2 ? tokens[2].toInt : 8080
    return NodeId(id, h, p, hp, zone, gen)
  }

  override Int compare(Obj that)
  {
    other := (NodeId)that
    cmp := this.id <=> other.id
    if (cmp != 0) return cmp
    return this.generation <=> other.generation
  }

  override Bool equals(Obj? that)
  {
    if (that isnot NodeId) return false
    other := (NodeId)that
    return this.id == other.id && this.generation == other.generation
  }

  override Int hash()
  {
    return id.hash.xor(generation)
  }

  override Str toStr()
  {
    return "$id($host:$port)"
  }
}
