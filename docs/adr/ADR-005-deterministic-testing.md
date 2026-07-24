# ADR-005: Deterministic Testing

## Status

Accepted

## Context

Timing-based tests often become flaky and difficult to maintain.

## Decision

Tests should rely on controlled fake implementations rather than delays.

Task.sleep should never define correctness.

## Consequences

### Advantages

- Stable CI
- Repeatable tests
- Faster execution
- Easier debugging

### Trade-offs

- Requires additional test utilities
