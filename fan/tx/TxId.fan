**
** TxId: Globally unique distributed transaction identifier incorporating
** originating node identity, timestamp, and monotonic counter.
**
const class TxId
{
  const NodeId originNode
  const Int timestamp
  const Int sequence

  new make(NodeId originNode, Int sequence, Int timestamp := DateTime.now.toJava)
  {
    this.originNode = originNode
    this.sequence   = sequence
    this.timestamp  = timestamp
  }

  override Int hash()
  {
    return originNode.hash.xor(sequence.hash).xor(timestamp.hash)
  }

  override Bool equals(Obj? that)
  {
    other := that as TxId
    if (other == null) return false
    return originNode == other.originNode && sequence == other.sequence && timestamp == other.timestamp
  }

  override Str toStr()
  {
    return "Tx(${originNode.id}:${timestamp}:${sequence})"
  }
}
