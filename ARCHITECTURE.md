# GitHubClient Architecture

## Overview

GitHubClient uses MVVM, repository abstractions, constructor-based dependency
injection, and Swift concurrency. The architecture is organized into folders
inside one application target; the boundaries are conventions rather than
separate Swift modules.

```text
SwiftUI Views
      │
      ▼
ViewModels and observable presentation state
      │
      ▼
Domain models and repository protocols
      ▲
      │
Data repositories, API client, caches, and persistence
```

There is no separate use-case layer. ViewModels coordinate the small repository
protocols directly.

## Presentation

Presentation code lives in `Features`, `Shared`, `ContentView.swift`, and the
typed navigation route under `App`.

Views:

- render observable state;
- forward user actions;
- declare navigation and lifecycle hooks;
- do not access URLSession or UserDefaults.

ViewModels:

- run on `MainActor`;
- own feature state and task handles;
- depend on Domain repository protocols;
- cancel owned tasks and reject stale completions with request identities or
  generations.

`AppError` and `RepositorySummaryRow` live in the `Shared` folder because they
are used by multiple features. `Shared` is not a separate module.

## Domain

`Domain` contains immutable repository models and two `Sendable` repository
protocols:

- `RepositoriesRepository`
- `FavoritesRepository`

Domain models use Foundation value types such as `URL` and `Date`, but do not
reference SwiftUI, URLSession, UserDefaults, API DTOs, or concrete Data
implementations.

## Data

`Data` contains:

- `GitHubAPIClient` and typed `GitHubEndpoint` values;
- API response DTOs and DTO-to-domain mapping;
- `GitHubRepositoriesRepository`;
- process-local search and details caches;
- `UserDefaultsFavoritesRepository`.

`GitHubRepositoriesRepository` is the boundary that maps `GitHubAPIError` into
stable `AppError` values. GitHub diagnostics remain in Data.

The search and details caches are actor-isolated, cache-first, process-local,
and currently have no expiration or capacity policy.

Favorites persistence stores a JSON-encoded sorted array of repository IDs. It
does not persist repository DTOs or full search results.

## Dependency Construction

`AppContainer.live` is the composition root. It creates:

- one `GitHubAPIClient`;
- one `GitHubRepositoriesRepository`;
- one `UserDefaultsFavoritesRepository`;
- one shared `FavoritesStore`.

`ContentView` injects those dependencies into Search, Favorites, and Repository
Details ViewModels. Views and ViewModels do not construct concrete Data
repositories.

## Cross-Feature Favorite State

`FavoritesStore` is intentionally application-wide presentation state even
though its source file is under `Features/Favorites`.

The same observable instance is used by:

- Search;
- Repository Details;
- Favorites List.

It owns the in-memory favorite ID set, performs optimistic updates, serializes
writes per repository ID, rolls back current failed writes, and prevents stale
write completion from overwriting newer intent.

## Feature State

Search uses an explicit primary phase plus an independent pagination state.

Repository Details uses:

- `RepositoryDetailsPrimaryState` for details;
- `RepositoryReadmeViewState` for independently loaded README content.

Favorites List uses `FavoritesViewState`, including initialization, loading,
empty, loaded, partial-failure metadata, refresh, and failure representation.

## Concurrency

The project uses `async`/`await`, actor isolation, owned `Task` instances, and a
bounded task group for Favorites List loading.

Relevant safeguards include:

- `MainActor` ViewModels and observable stores;
- actor-isolated API, caches, and persistence;
- explicit task cancellation in lifecycle methods and deinitializers;
- request IDs or generations for stale-response rejection;
- duplicate request guards;
- per-ID favorite-write serialization;
- a Favorites List concurrency limit of four requests.

The project does not use `Task.detached`, semaphores, or blocking waits in
production code.

## Navigation

`AppRoute` provides typed repository navigation. Search and Favorites each own
an independent `NavigationStack`. Both construct Repository Details through the
same injected repositories and shared `FavoritesStore`.

## Testing

The unit-test target uses Swift Testing. It covers endpoint construction,
decoding, mapping, repositories, caches, state transitions, cancellation,
stale responses, pagination, persistence, optimistic writes, bounded
concurrency, retry, refresh, and partial failures.

Controlled continuations are used for the most involved favorites concurrency
tests. Some older tests still use short sleeps or bounded polling; therefore
the suite reduces timing dependence but does not eliminate it. There is
currently no UI-test target or CI workflow.
