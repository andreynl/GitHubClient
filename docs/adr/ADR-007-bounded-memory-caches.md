# ADR-007: Bounded Process-Local Memory Caches

## Status

Accepted

## Context

Search pages and repository details benefit from avoiding duplicate requests
within one application process. Permanently fresh, unbounded dictionaries can
serve stale data indefinitely and grow without a defined limit.

## Decision

The Data layer keeps actor-isolated, process-local caches with one centralized
policy:

- search pages remain fresh for five minutes with a capacity of 100 entries;
- repository details remain fresh for five minutes with a capacity of 50
  entries;
- expired entries are treated as misses;
- capacity eviction is deterministic least-recently-used eviction;
- a synchronous, `Sendable` clock abstraction supplies timestamps so tests can
  advance time without sleeping.

This policy does not add persistence, background refresh, or a user-visible
refresh contract.

## Consequences

### Advantages

- Stale data has a defined lifetime.
- Memory growth is bounded.
- Eviction and freshness are deterministic and testable.
- Actor isolation protects cache mutation.

### Trade-offs

- Cached data is still lost when the app process ends.
- Five-minute freshness is a product-neutral default rather than a
  server-directed policy.
- Explicit invalidation and user-controlled refresh remain separate future
  decisions.
