**
** LockLease: Distributed lease descriptor granting mutual exclusion with a monotonic fencing token.
**
** Reference:
** Kleppmann, "How to do distributed locking", 2016.
** Fencing tokens ensure storage nodes reject stale writes from paused or slow clients.
**
const class LockLease
{
  const Str lockName
  const Str ownerId
  const Int fencingToken
  const Int expiresAtMillis

  new make(Str lockName, Str ownerId, Int fencingToken, Int expiresAtMillis)
  {
    this.lockName        = lockName
    this.ownerId         = ownerId
    this.fencingToken    = fencingToken
    this.expiresAtMillis = expiresAtMillis
  }

  **
  ** Check if lease has expired at nowMillis.
  **
  Bool isExpired(Int nowMillis := DateTime.now.toJava)
  {
    return nowMillis >= expiresAtMillis
  }
}

**
** NexusLock: Distributed reentrant mutual exclusion primitive with lease timeouts
** and monotonic fencing tokens to prevent split-brain storage corruptions.
**
class NexusLock
{
  private Str name
  private Str? currentOwner := null
  private Int currentToken := 0
  private Int expiresAt := 0
  private Int holdCount := 0
  private Int tokenSeq := 0

  new make(Str name)
  {
    this.name = name
  }

  **
  ** Lock resource name.
  **
  Str lockName() { return name }

  **
  ** Current lock owner ID, or null if unlocked or expired.
  **
  Str? owner(Int nowMillis := DateTime.now.toJava)
  {
    if (currentOwner != null && nowMillis >= expiresAt)
    {
      currentOwner = null
      holdCount = 0
    }
    return currentOwner
  }

  **
  ** Current monotonic fencing token.
  **
  Int fencingToken() { return currentToken }

  **
  ** Check if lock is currently held.
  **
  Bool isLocked(Int nowMillis := DateTime.now.toJava)
  {
    return owner(nowMillis) != null
  }

  **
  ** Current reentrant hold count.
  **
  Int getHoldCount() { return holdCount }

  **
  ** Attempt to acquire lock with lease duration.
  ** Returns LockLease if acquired or re-entered, null if lock is held by another owner.
  **
  LockLease? tryLock(Str ownerId, Int leaseDurationMillis := 10_000, Int nowMillis := DateTime.now.toJava)
  {
    // Check if expired
    if (currentOwner != null && nowMillis >= expiresAt)
    {
      currentOwner = null
      holdCount = 0
    }

    // Case 1: Unlocked
    if (currentOwner == null)
    {
      currentOwner = ownerId
      tokenSeq++
      currentToken = tokenSeq
      expiresAt = nowMillis + leaseDurationMillis
      holdCount = 1
      return LockLease(name, ownerId, currentToken, expiresAt)
    }

    // Case 2: Reentrant acquisition by same owner
    if (currentOwner == ownerId)
    {
      holdCount++
      expiresAt = nowMillis + leaseDurationMillis
      return LockLease(name, ownerId, currentToken, expiresAt)
    }

    // Case 3: Held by another active owner
    return null
  }

  **
  ** Release one reentrant hold level.
  ** Returns true if released, false if not held by caller.
  **
  Bool unlock(Str ownerId)
  {
    if (currentOwner == null || currentOwner != ownerId)
    {
      return false
    }

    holdCount--
    if (holdCount <= 0)
    {
      currentOwner = null
      holdCount = 0
      expiresAt = 0
    }
    return true
  }

  **
  ** Administratively break and release the lock.
  **
  Void forceUnlock()
  {
    currentOwner = null
    holdCount = 0
    expiresAt = 0
  }
}
