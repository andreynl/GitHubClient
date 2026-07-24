# GitHubClient Roadmap

This roadmap records the phases represented by the repository history. It does
not promise unscheduled product features.

## Completed

### Phase 1 — Repository Search Foundation

- GitHub API client and typed search endpoint
- Domain repository abstraction and DTO mapping
- Debounced search, explicit states, pagination, cancellation, and retry
- Process-local actor-backed search cache
- Unit tests for networking, mapping, state transitions, and stale responses

### Phase 2.1 — Repository Details Foundation

- Typed navigation from search results
- Repository details domain model, endpoint, DTO, and mapping
- Process-local actor-backed details cache
- Details ViewModel and explicit primary state
- Loading, success, failure, cancellation, and retry coverage

### Phase 2.2 — Repository Details Polish

- Owner avatar and repository metadata
- Statistics, topics, archive state, formatted dates, and external links
- Dynamic Type-compatible SwiftUI composition and accessibility labels

### Phase 3 — README Viewer

- Raw-text repository README endpoint
- README loading independent from primary repository details
- Graceful README failure that does not replace loaded details

### Architecture Hardening

- Data-to-presentation error boundary through `AppError`
- Structured Data-layer diagnostics
- Cancellation transition fixes
- Invalid Repository Details primary-state combinations removed

### Phase 4 — Persistent Favorites

- Repository-ID persistence through a Domain repository abstraction
- One shared `FavoritesStore`
- Search and Details favorite controls
- Optimistic updates, rollback, serialized per-ID writes, and stale-write
  protection

### Phase 5 — Favorites Screen

- Search and Favorites tabs with independent typed navigation stacks
- Repository summary loading by persisted favorite ID
- Bounded concurrent loading
- Deterministic ordering, refresh, retry, and partial-failure states
- Shared repository-row presentation

## In Progress

### Phase 5.1 — Repository Hardening

- Align public documentation with the implementation
- Add the declared license
- Track repository engineering instructions
- Remove accidental Xcode project churn
- Verify repository hygiene, build, and tests

## Planned

### Phase 6

Phase 6 scope must be planned and approved before implementation. Candidates
identified by the production-readiness review include:

- favorites persistence failure presentation
- recoverable cancellation UI states
- explicit cache capacity and freshness
- GitHub secondary rate-limit handling
- more deterministic asynchronous tests
- minimal CI and UI smoke coverage

These are candidates, not completed or committed scope.

## Unscheduled Ideas

- offline repository-content support
- image caching
- advanced search filters and history
- repository sorting
- user profiles
- localization
