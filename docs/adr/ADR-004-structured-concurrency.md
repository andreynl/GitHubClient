# ADR-004: Prefer Structured Concurrency

## Status

Accepted

## Context

The application performs asynchronous searches, refreshes, and cancellation.

Detached tasks make ownership harder to reason about.

## Decision

Prefer:

- async/await
- Task
- TaskGroup

Avoid Task.detached unless there is a compelling reason.

## Consequences

### Advantages

- Predictable lifetime
- Automatic cancellation propagation
- Easier reasoning
- Safer async code

### Trade-offs

- Requires understanding task hierarchy
