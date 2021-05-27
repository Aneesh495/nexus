**
** NexusAtomicLong: Distributed atomic 64-bit counter supporting Compare-And-Swap (CAS),
** arithmetic operations, and version tracking.
**
** Reference:
** Java java.util.concurrent.atomic.AtomicLong,
** Hazelcast IAtomicLong distributed counter.
**
class NexusAtomicLong
{
  private Str name
  private Int value
  private Int version := 0

  new make(Str name, Int initialValue := 0)
  {
    this.name  = name
    this.value = initialValue
  }

  **
  ** Atomic counter name.
  **
  Str atomicName() { return name }

  **
  ** Current 64-bit integer value.
  **
  Int get() { return value }

  **
  ** Monotonic version generation incremented on every mutation.
  **
  Int currentVersion() { return version }

  **
  ** Unconditionally set new value.
  **
  Void set(Int newValue)
  {
    this.value = newValue
    this.version++
  }

  **
  ** Atomically set new value and return previous value.
  **
  Int getAndSet(Int newValue)
  {
    prev := value
    this.value = newValue
    this.version++
    return prev
  }

  **
  ** Atomically add delta and return previous value.
  **
  Int getAndAdd(Int delta)
  {
    prev := value
    this.value += delta
    this.version++
    return prev
  }

  **
  ** Atomically add delta and return updated value.
  **
  Int addAndGet(Int delta)
  {
    this.value += delta
    this.version++
    return value
  }

  **
  ** Atomically increment value by 1 and return updated value.
  **
  Int incrementAndGet() { return addAndGet(1) }

  **
  ** Atomically decrement value by 1 and return updated value.
  **
  Int decrementAndGet() { return addAndGet(-1) }

  **
  ** Atomically set value to update if current value equals expected value (CAS).
  ** Returns true if successful, false otherwise.
  **
  Bool compareAndSet(Int expect, Int update)
  {
    if (this.value == expect)
    {
      this.value = update
      this.version++
      return true
    }
    return false
  }
}

**
** NexusAtomicReference: Distributed atomic reference container with CAS semantics.
**
class NexusAtomicReference
{
  private Str name
  private Obj? value
  private Int version := 0

  new make(Str name, Obj? initialValue := null)
  {
    this.name  = name
    this.value = initialValue
  }

  **
  ** Reference identifier name.
  **
  Str referenceName() { return name }

  **
  ** Current referenced object.
  **
  Obj? get() { return value }

  **
  ** Current mutation version.
  **
  Int currentVersion() { return version }

  **
  ** Unconditionally set new reference.
  **
  Void set(Obj? newValue)
  {
    this.value = newValue
    this.version++
  }

  **
  ** Atomically set new reference and return previous reference.
  **
  Obj? getAndSet(Obj? newValue)
  {
    prev := value
    this.value = newValue
    this.version++
    return prev
  }

  **
  ** Atomically set reference to update if current reference equals expected (CAS).
  ** Returns true if successful, false otherwise.
  **
  Bool compareAndSet(Obj? expect, Obj? update)
  {
    if (this.value == expect)
    {
      this.value = update
      this.version++
      return true
    }
    return false
  }
}
