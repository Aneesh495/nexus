**
** ContinuousQueryPredicate: Filter specification evaluated on key-value mutations.
**
mixin ContinuousQueryPredicate
{
  **
  ** Evaluate predicate against a key and value pair.
  **
  abstract Bool matches(Str key, Obj? val)
}

**
** PrefixPredicate: Matches keys having a specified prefix.
**
const class PrefixPredicate : ContinuousQueryPredicate
{
  const Str prefix

  new make(Str prefix)
  {
    this.prefix = prefix
  }

  override Bool matches(Str key, Obj? val)
  {
    return key.startsWith(prefix)
  }
}

**
** ExactMatchPredicate: Matches entries with exact key and value equivalence.
**
const class ExactMatchPredicate : ContinuousQueryPredicate
{
  const Str targetKey
  const Obj? targetVal

  new make(Str targetKey, Obj? targetVal)
  {
    this.targetKey = targetKey
    this.targetVal = targetVal
  }

  override Bool matches(Str key, Obj? val)
  {
    return key == targetKey && val == targetVal
  }
}

**
** ContinuousQuery: Stream subscription dispatching events matching a predicate.
**
class ContinuousQuery
{
  private ContinuousQueryPredicate predicate
  private |MapEventType, Str, Obj?| callback

  new make(ContinuousQueryPredicate predicate, |MapEventType, Str, Obj?| callback)
  {
    this.predicate = predicate
    this.callback  = callback
  }

  **
  ** Evaluate and dispatch event if it matches the predicate filter.
  **
  Void publishEvent(MapEventType evt, Str key, Obj? val)
  {
    if (predicate.matches(key, val))
    {
      callback(evt, key, val)
    }
  }
}
