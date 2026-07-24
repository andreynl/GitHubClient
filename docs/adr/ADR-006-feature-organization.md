# ADR-006: Feature-Based Project Structure

## Status

Accepted

## Context

As the application grows, organizing code by technical layer alone makes navigation harder.

## Decision

Presentation code is organized primarily by feature inside the application
target.

Code used by multiple features may live in the `Shared` folder. `Shared` is a
folder, not a separate Swift module.

`FavoritesStore` is intentionally located under `Features/Favorites` while
serving Search, Repository Details, and Favorites List as their single shared
favorite-state owner.

## Consequences

### Advantages

- Better discoverability
- Easier feature ownership
- Reduced coupling between features

### Trade-offs

- Shared code requires discipline to avoid becoming a dumping ground
