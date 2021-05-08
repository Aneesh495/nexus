**
** RaftRpcType: Identifiers for wire framing of consensus messages.
**
enum class RaftRpcType
{
  request_vote_req,
  request_vote_resp,
  append_entries_req,
  append_entries_resp,
  install_snapshot_req,
  install_snapshot_resp,
  read_index_req,
  read_index_resp
}

**
** RequestVoteArgs: Candidate request to gather quorum votes during election.
**
const class RequestVoteArgs
{
  const Int term
  const NodeId candidateId
  const Int lastLogIndex
  const Int lastLogTerm
  const Bool isPreVote

  new make(
    Int term,
    NodeId candidateId,
    Int lastLogIndex,
    Int lastLogTerm,
    Bool isPreVote := false)
  {
    this.term         = term
    this.candidateId  = candidateId
    this.lastLogIndex = lastLogIndex
    this.lastLogTerm  = lastLogTerm
    this.isPreVote    = isPreVote
  }
}

**
** RequestVoteReply: Response acknowledging or denying candidate vote.
**
const class RequestVoteReply
{
  const Int term
  const Bool voteGranted
  const NodeId voterId

  new make(Int term, Bool voteGranted, NodeId voterId)
  {
    this.term        = term
    this.voteGranted = voteGranted
    this.voterId     = voterId
  }
}

**
** AppendEntriesArgs: Leader log replication and heartbeat RPC.
**
const class AppendEntriesArgs
{
  const Int term
  const NodeId leaderId
  const Int prevLogIndex
  const Int prevLogTerm
  const RaftLogEntry[] entries
  const Int leaderCommit

  new make(
    Int term,
    NodeId leaderId,
    Int prevLogIndex,
    Int prevLogTerm,
    RaftLogEntry[] entries,
    Int leaderCommit)
  {
    this.term         = term
    this.leaderId     = leaderId
    this.prevLogIndex = prevLogIndex
    this.prevLogTerm  = prevLogTerm
    this.entries      = entries.toImmutable
    this.leaderCommit = leaderCommit
  }

  Bool isHeartbeat() { return entries.isEmpty }
}

**
** AppendEntriesReply: Follower response confirming match or signaling conflict hint.
**
const class AppendEntriesReply
{
  const Int term
  const Bool success
  const NodeId followerId
  const Int matchIndex
  const Int conflictHintIndex

  new make(
    Int term,
    Bool success,
    NodeId followerId,
    Int matchIndex,
    Int conflictHintIndex := 0)
  {
    this.term              = term
    this.success           = success
    this.followerId        = followerId
    this.matchIndex        = matchIndex
    this.conflictHintIndex = conflictHintIndex
  }
}

**
** InstallSnapshotArgs: Streamed snapshot chunk sent to catch up trailing replicas.
**
const class InstallSnapshotArgs
{
  const Int term
  const NodeId leaderId
  const Int lastIncludedIndex
  const Int lastIncludedTerm
  const Int offset
  const Str data
  const Bool done

  new make(
    Int term,
    NodeId leaderId,
    Int lastIncludedIndex,
    Int lastIncludedTerm,
    Int offset,
    Str data,
    Bool done := true)
  {
    this.term              = term
    this.leaderId          = leaderId
    this.lastIncludedIndex = lastIncludedIndex
    this.lastIncludedTerm  = lastIncludedTerm
    this.offset            = offset
    this.data              = data
    this.done              = done
  }
}

**
** InstallSnapshotReply: Follower acknowledgment of snapshot installation.
**
const class InstallSnapshotReply
{
  const Int term
  const NodeId followerId

  new make(Int term, NodeId followerId)
  {
    this.term       = term
    this.followerId = followerId
  }
}

**
** ReadIndexArgs: Query read barrier index for linearizable queries without WAL writes.
**
const class ReadIndexArgs
{
  const Int reqId
  const NodeId requesterId

  new make(Int reqId, NodeId requesterId)
  {
    this.reqId       = reqId
    this.requesterId = requesterId
  }
}

**
** ReadIndexReply: Leader confirmation of quorum-verified read index.
**
const class ReadIndexReply
{
  const Int reqId
  const Int readIndex
  const Bool success

  new make(Int reqId, Int readIndex, Bool success)
  {
    this.reqId     = reqId
    this.readIndex = readIndex
    this.success   = success
  }
}

**
** RaftMessageCodec: Serializes and deserializes consensus RPC payloads to/from ByteBuf.
**
class RaftMessageCodec
{
  **
  ** Encode RequestVoteArgs into ByteBuf.
  **
  static ByteBuf encodeRequestVote(RequestVoteArgs args)
  {
    buf := ByteBuf(64)
    buf.writeByte(RaftRpcType.request_vote_req.ordinal)
    buf.writeVarInt(args.term)
    buf.writeUtf8(args.candidateId.id)
    buf.writeVarInt(args.lastLogIndex)
    buf.writeVarInt(args.lastLogTerm)
    buf.writeByte(args.isPreVote ? 1 : 0)
    return buf
  }

  **
  ** Decode RequestVoteArgs from ByteBuf.
  **
  static RequestVoteArgs decodeRequestVote(ByteBuf buf)
  {
    type := buf.readByte
    term := buf.readVarInt
    candId := NodeId(buf.readUtf8)
    lastIdx := buf.readVarInt
    lastTerm := buf.readVarInt
    isPreVote := (buf.readByte != 0)
    return RequestVoteArgs(term, candId, lastIdx, lastTerm, isPreVote)
  }

  **
  ** Encode AppendEntriesReply into ByteBuf.
  **
  static ByteBuf encodeAppendEntriesReply(AppendEntriesReply reply)
  {
    buf := ByteBuf(64)
    buf.writeByte(RaftRpcType.append_entries_resp.ordinal)
    buf.writeVarInt(reply.term)
    buf.writeByte(reply.success ? 1 : 0)
    buf.writeUtf8(reply.followerId.id)
    buf.writeVarInt(reply.matchIndex)
    buf.writeVarInt(reply.conflictHintIndex)
    return buf
  }

  **
  ** Decode AppendEntriesReply from ByteBuf.
  **
  static AppendEntriesReply decodeAppendEntriesReply(ByteBuf buf)
  {
    type := buf.readByte
    term := buf.readVarInt
    success := (buf.readByte != 0)
    fId := NodeId(buf.readUtf8)
    matchIdx := buf.readVarInt
    hintIdx := buf.readVarInt
    return AppendEntriesReply(term, success, fId, matchIdx, hintIdx)
  }
}
