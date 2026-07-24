# ADR-004: Prefer Swift Concurrency with Explicit Task Ownership

## Status

Accepted

## Context

The application performs asynchronous searches, refreshes, persistence, and
cancellation. Some UI workflows must start work from synchronous actions, so
ViewModels own explicit `Task` handles in addition to using task groups.

Detached and unowned fire-and-forget tasks make lifetime and cancellation
harder to reason about.

## Decision

Use:

- async/await
- owned `Task` instances for ViewModel workflows
- task groups for bounded concurrent child work
- actors for shared mutable Data-layer state

Store and cancel task handles where work can outlive the initiating call.
Protect UI state from stale completions with request identities or generations.
Avoid `Task.detached` unless a documented ownership requirement justifies it.

## Consequences

### Advantages

- Explicit lifetime and cancellation
- Child-task cancellation inside task groups
- Easier reasoning
- Safer async code

### Trade-offs

- Requires explicit task ownership for work launched from synchronous UI actions
