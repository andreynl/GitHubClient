# ADR-003: FavoritesStore as Single Source of Truth

## Status

Accepted

## Context

Repository favorite state appears in multiple screens.

Duplicated ownership would eventually lead to inconsistent UI state.

## Decision

FavoritesStore owns all favorite identifiers.

Every screen observes the same source of truth.

## Consequences

### Advantages

- Consistent UI
- No duplicated state
- Easier synchronization

### Trade-offs

- Requires dependency injection
- Slightly more coordination between features
