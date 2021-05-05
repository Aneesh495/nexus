**
** RaftEntryType: Functional classification of a replicated state machine entry.
**
enum class RaftEntryType
{
  noop,
  command,
  configuration,
  barrier
}

**
** RaftLogEntry: Immutable log record replicated across quorum nodes.
**
const class RaftLogEntry
{
  const Int index
  const Int term
  const RaftEntryType type
  const Str payload
  const Int clientReqId

  new make(
    Int index,
    Int term,
    RaftEntryType type := RaftEntryType.command,
    Str payload := "",
    Int clientReqId := 0)
  {
    this.index       = index
    this.term        = term
    this.type        = type
    this.payload     = payload
    this.clientReqId = clientReqId
  }

  override Str toStr()
  {
    return "LogEntry(idx=$index, term=$term, type=$type.name, len=${payload.size})"
  }
}
