# ADR-005: Deterministic Testing

## Status

Accepted

## Context

Timing-based tests often become flaky and difficult to maintain.

## Decision

Prefer controlled fake implementations, continuations, and observable
conditions over arbitrary delays.

New concurrency tests should not use `Task.sleep` as their only ordering
mechanism. A bounded clock or polling deadline may be used to prevent a failed
test from hanging.

The repository contains older short-delay tests. They remain accepted technical
debt until replaced by controlled synchronization in an approved hardening
scope.

## Consequences

### Advantages

- More repeatable tests
- Faster failure diagnosis
- Easier debugging

### Trade-offs

- Requires additional test utilities
- Existing timing-based tests require incremental migration
