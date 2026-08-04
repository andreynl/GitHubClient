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

### Phase 5.1 — Repository Hardening

- Align public documentation with the implementation
- Add the declared license
- Track repository engineering instructions
- Remove accidental Xcode project churn
- Verify repository hygiene, build, and tests

### Phase 5.2 — Public Release Readiness

- Add the required-reason privacy manifest for app-owned favorites persistence
- Integrate complete application icon artwork
- Add an adaptive static light and dark launch presentation
- Add GitHub Actions build and test validation
- Correct roadmap status and clarify the cross-layer `AppError` contract

### Repository Remediation

- Align app and test deployment targets with the intended iOS 26.0 baseline
- Document the verified Swift 5 language mode used by the Xcode 26 toolchain
- Validate committed whitespace ranges and add static analysis in CI
- Pin the GitHub REST API version and classify primary and secondary throttling
- Propagate GitHub incomplete-search responses as non-fatal presentation state
- Add bounded, expiring in-memory caches with deterministic eviction and clocks
- Add deterministic local SwiftUI preview dependencies
- Add an English String Catalog and pluralized partial-failure copy
- Harden the static launch layout without modifying the approved artwork
- Complete signed iPhone and iPad Launch Screen runtime validation
- Confirm the black fallback came from installing a build produced with
  `CODE_SIGNING_ALLOWED=NO`; signed Simulator builds render the approved Light
  and Dark artwork correctly

## Pre-Phase 6 — Engineering Hardening

- Favorites initial-load failure presentation and retry
- Release build validation in CI

## Phase 6 — Search History

Planning required before implementation.

## Engineering Backlog

### Technical Improvements

- Recoverable cancellation UI states
- Replace remaining delay-driven async tests with controlled gates
- Minimal UI smoke coverage
- Independent README retry
- Preserve raw search input during normalized requests

### Future Product Ideas

- Offline repository-content support
- Image caching
- Advanced search filters and history
- Repository sorting
- User profiles
- Additional localizations
