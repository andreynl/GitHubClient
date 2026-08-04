# Phase 6 — Search History Design

## Status

Approved for implementation planning.

## Context

GitHubClient currently supports debounced public-repository search, pagination,
repository details, README content, and persisted favorites. Search has explicit
primary and pagination state, MainActor-isolated ViewModel ownership, injected
Domain repository abstractions, cancellation, and stale-response protection.

Phase 6 adds persistent Search History to the existing Search screen. The
feature follows the project's accepted Clean Architecture, MVVM, Repository,
dependency-injection, AppError, Swift Concurrency, explicit-state, and
deterministic-testing conventions.

Implementation starts only after the mandatory Pre-Phase 6 Engineering
Hardening scope is completed and approved.

## Goals

1. Persist successful repository-search queries.
2. Display recent searches newest first on the existing Search screen.
3. Remove case-insensitive duplicates while preserving the latest trimmed
   spelling.
4. Enforce an injected maximum capacity of 10 entries in live configuration.
5. Start a new search immediately when the user selects a history entry.
6. Clear all history without confirmation.
7. Keep history loading, mutation, and error state independent from GitHub
   search state.
8. Preserve layer boundaries and deterministic concurrency behavior without
   adding a global store or unnecessary abstraction.

## Non-goals

Phase 6 does not add:

- autocomplete;
- local or remote search suggestions;
- GitHub API suggestions;
- filtering history while the user types;
- recent repositories;
- analytics;
- cloud sync;
- a separate Search History screen;
- a new application module;
- a use-case layer;
- a global `SearchHistoryStore`;
- a UI-test target;
- unrelated Search, Favorites, Details, cache, or networking changes.

## Feature Overview

Search History records successful initial repository searches and makes them
available from the existing Search screen.

A search is successful for history purposes when:

- the initial search request completes successfully;
- the response is accepted by the current Search request identity;
- the response is not stale;
- the request was not cancelled.

Both non-empty and empty successful responses are recorded. History is not
updated for network, server, decoding, cancellation, or discarded stale
responses.

Search History represents successful user searches rather than successful
repository discovery. A query returning zero repositories may produce results
in the future and remains reusable.

## User Experience

### Visibility

When the search query is empty, the Search screen is in its idle state, and
history contains entries, the idle content becomes a `Recent Searches`
section.

The history area is eligible for display only when:

- the search query is empty;
- the primary Search state is idle; and
- history contains entries, is loading, or exposes a visible history error.

An empty successful history load preserves the existing Search idle fallback.
It does not render an empty `Recent Searches` section.

Starting to type hides Search History immediately and returns to the existing
search flow. History is not filtered from partial input and is not displayed
during primary loading, results, empty-results, or error states.

### Entries

- Entries are displayed newest first.
- Selecting an entry fills the search query and immediately starts a new
  initial search without waiting for the typing debounce.
- Selection does not move the entry immediately.
- The selected entry moves to the front only if its new initial search
  succeeds and the response is accepted.

### Clear

- The `Clear` action deletes the complete history immediately.
- No confirmation dialog or alert is shown.
- Existing entries remain visible until persistence confirms success.
- Successful clear returns Search to its existing empty idle state.
- Failed clear preserves the current entries and presents a compact,
  history-only error with Retry.

## Query Semantics

`SearchHistoryRepository.recordSuccessfulQuery(_:)` receives the query produced
by the accepted successful search flow.

The repository:

- trims leading and trailing whitespace;
- compares duplicate queries case-insensitively;
- treats queries that differ only by case or surrounding whitespace as
  duplicates;
- removes an existing duplicate;
- inserts the latest trimmed spelling at the front;
- preserves that latest spelling for persistence and display;
- does not automatically lowercase the display value;
- removes oldest entries from the end when capacity is exceeded.

Examples:

```text
Existing: "Swift"
New:      " swift "
Result:   "swift" becomes the newest entry
```

```text
Existing: "SwiftUI"
New:      "SWIFTUI"
Result:   "SWIFTUI" becomes the newest entry
```

Internal normalization may be used only for duplicate comparison.
`SearchViewModel` does not pre-normalize a query for persistence.

## Architecture

The feature follows the existing dependency direction:

```text
SearchView
    │
    ▼
SearchViewModel
    │
    ▼
SearchHistoryRepository
    ▲
    │
UserDefaultsSearchHistoryRepository
```

Observable architectural boundaries are:

- Domain owns `SearchHistoryEntry` and `SearchHistoryRepository`;
- Data owns the persistence implementation and raw-error mapping;
- Presentation owns history UI state and coordination;
- `AppContainer` owns live dependency construction;
- dependencies continue to point toward Domain abstractions.

Concrete file layout may change during implementation planning when these
boundaries and dependency direction remain intact.

No shared observable store is introduced. Search History currently belongs to
one feature, so `SearchViewModel` remains its presentation owner.

## Domain Model

### SearchHistoryEntry

`SearchHistoryEntry` is:

- immutable;
- `Equatable`;
- `Sendable`;
- a holder of the latest trimmed display query;
- free of timestamps because persisted newest-first array order is
  authoritative.

The model contains no persistence, SwiftUI, networking, or DTO concerns.

## Repository Abstraction

`SearchHistoryRepository` is a `Sendable` Domain protocol with semantic
operations equivalent to:

```swift
func loadHistory() async throws -> [SearchHistoryEntry]
func recordSuccessfulQuery(_ query: String) async throws -> [SearchHistoryEntry]
func clearHistory() async throws
```

The abstraction owns the complete atomic behavior for:

- loading history;
- recording a successful query;
- clearing history;
- trimming;
- duplicate matching;
- latest-spelling preservation;
- newest-first ordering;
- capacity enforcement.

Load and record return authoritative newest-first lists. Clear returns only
after persistence succeeds; `SearchViewModel` then makes the empty list
authoritative.

The ViewModel does not load an array, mutate it, and save it back. This prevents
business rules and read-modify-write behavior from leaking into Presentation.

## Persistence

`UserDefaultsSearchHistoryRepository` is actor-isolated.

It:

- persists a JSON-encoded array of query strings;
- stores array order as newest first;
- uses a dedicated key separate from Favorites;
- receives `UserDefaults`, its storage key, and maximum capacity through
  initialization;
- uses capacity 10 in live composition;
- performs record as one actor-isolated read-modify-write operation;
- completes clear only after the persistence API accepts the mutation;
- returns the authoritative list after load and record;
- does not persist DTOs, repository results, timestamps, or normalized display
  values.

The maximum capacity is an implementation configuration value. Changing it
later does not require changing the feature's public behavior or architecture.

The design does not claim synchronous physical disk flushing from
`UserDefaults`. Repository success means the configured persistence API
accepted the encoded value.

## Dependency Injection

`AppContainer` constructs:

- one live `UserDefaultsSearchHistoryRepository`;
- its live capacity of 10;
- the existing repositories and shared FavoritesStore.

`ContentView` passes the Search History repository into `SearchViewModel`.
`SearchViewModel` depends on the Domain protocol, and `SearchView` receives no
persistence dependency.

No concrete Data repository is created inside a View or ViewModel.

## Presentation State

Search History has independent presentation state. It does not extend or
replace the existing primary Search and pagination states.

The state model is equivalent to:

- `idle`;
- `loading`;
- `loaded(entries)`;
- `updating(entries, operation)`;
- `failed(entries, error, retryOperation)`.

The operation metadata is equivalent to:

- `load`;
- `record(query)`;
- `clear`.

Operation metadata supports explicit transitions and retry. It does not own
persistence or normalization rules.

Updating state is visible only when it has existing entries or meaningful
inline progress content.

## State Transitions

### Initial load

```text
idle
→ loading
→ loaded(entries)
```

```text
idle
→ loading
→ failed([], error, load)
```

History loads once from Search lifecycle. Duplicate lifecycle triggers do not
start duplicate loads.

### Successful initial search

```text
GitHub response succeeds
→ response passes current request and stale checks
→ primary Search state is applied
→ record(query) is accepted
→ repository returns authoritative entries
→ history becomes loaded(updatedEntries)
```

Empty successful results follow the same flow. Failure, cancellation, or stale
rejection never accepts a record operation.

### Record failure

```text
loaded(existingEntries)
→ updating(existingEntries, record(query))
→ failed(existingEntries, error, record(query))
```

Primary Search results remain unchanged.

### Tap-to-search

A dedicated ViewModel action:

- assigns the selected display query to Search state;
- cancels current Search and pagination tasks;
- advances the existing Search request identity;
- starts a new initial search immediately;
- does not wait for the typing debounce.

### Clear

```text
loaded(entries)
→ updating(entries, clear)
→ loaded([])
```

```text
loaded(entries)
→ updating(entries, clear)
→ failed(entries, error, clear)
```

The empty list becomes authoritative only after `clearHistory()` succeeds.

### Retry

Retry:

- repeats only the failed operation exposed by current history state;
- enqueues a new instance of that operation;
- does not replay unrelated completed or queued operations;
- uses current authoritative entries when determining presentation state.

## SearchViewModel Integration

`SearchViewModel`:

- coordinates history with the existing Search flow;
- exposes independent history presentation state;
- triggers repository operations;
- owns history operation scheduling;
- records only accepted successful initial searches;
- passes the successful-flow query to the repository without persistence
  normalization;
- preserves primary results during history failures;
- retries only the currently exposed failed history operation;
- updates history from repository-returned authoritative values;
- makes `[]` authoritative only after successful clear.

It does not:

- access `UserDefaults`;
- encode or decode history;
- trim persistence input;
- implement duplicate comparison;
- enforce ordering or capacity;
- translate raw persistence errors;
- couple history failure to primary Search failure.

## Concurrency and Operation Ownership

`SearchViewModel` owns one private active history-operation task and a FIFO of
pending history operations.

A history operation is accepted when `SearchViewModel` appends it to the FIFO
on `MainActor`.

Only `SearchViewModel` may:

- enqueue a history operation;
- start the next operation;
- remove the active operation;
- update history presentation state.

The active item is removed before the next accepted item starts, regardless of
success, failure, or cancellation.

When an operation fails:

- appropriate authoritative entries are preserved;
- the failed operation becomes the exposed retry operation;
- the active item finishes and is removed;
- operations already accepted afterward continue;
- failure does not block a later explicit Clear.

When a later operation succeeds, its authoritative result replaces an older
presentation failure that is no longer relevant.

Externally observable concurrency guarantees are:

1. At most one history repository operation is active.
2. Operations accepted by `SearchViewModel` execute in FIFO order.
3. The resulting authoritative history matches the accepted operation
   sequence.
4. A later clear cannot be undone by an older record completion.
5. Repository mutation remains atomic inside its actor.
6. History presentation mutation occurs only on `MainActor`.
7. Persistence correctness does not depend on cancellation interrupting or
   rolling back an accepted mutation.

The internal queue representation is not part of the feature contract and may
change without changing these guarantees.

### Cancellation

When SearchViewModel-owned history work is cancelled:

- no further history presentation-state updates are emitted;
- queued ViewModel-owned operations are discarded;
- the active item is finished and removed;
- cancellation is not shown as an error.

Repository actor operations observe cancellation where practical. They may
check before starting a mutation and before committing an encoded value.

Once the persistence API accepts a mutation:

- the repository treats it as committed;
- it returns the authoritative result even if cancellation is observed
  immediately afterward;
- `SearchViewModel` may discard that result when its owning task was cancelled;
- persistence ordering does not depend on rolling back the accepted mutation.

The existing Search and pagination tasks, request identity, query matching,
page bookkeeping, cancellation, and stale-response checks continue to own
GitHub Search behavior.

## Error Handling

Search History uses the application-wide `AppError` boundary. A stable
`AppError.persistence` case is added because existing network-oriented cases
do not accurately describe local storage failure.

Its user-facing message remains general and understandable, equivalent to:

> Saved data could not be loaded or updated. Try again.

`UserDefaultsSearchHistoryRepository` maps storage, encoding, decoding, and
persisted-shape failures to `AppError.persistence` before they cross the Data
boundary.

`SearchViewModel`:

- does not inspect raw persistence errors;
- does not translate raw persistence failures;
- keeps cancellation distinguishable from persistence failure;
- never converts cancellation into visible history failure.

### Independent presentation

- History errors appear as compact inline content with Retry.
- Initial load failure is visible only while query is empty and primary Search
  is idle.
- Clear failure preserves current entries.
- Automatic record failure never replaces successful Search results.
- Primary Search failures and history failures remain independent.
- A later authoritative history success removes an obsolete history failure.

### Corrupt persisted data

When stored history cannot be decoded or violates the persisted shape:

- the repository throws `AppError.persistence`;
- it does not silently return an empty list;
- it does not delete, migrate, quarantine, overwrite, or replace the stored
  value;
- the ViewModel preserves any previously authoritative in-memory entries;
- Retry repeats only the failed repository operation.

Retry does not modify the corrupt value before trying again. Repeated retries
may therefore continue failing until behavior outside the approved Phase 6
scope corrects the stored value. This is intentional under the explicit-failure
policy.

Automatic recovery, reset UI, migration, and quarantine remain out of scope.

## Testing Strategy

All new asynchronous ordering tests use controlled fakes, checked
continuations, and explicit operation gates. `Task.sleep` does not define
correctness.

### Persistence coverage

Tests verify:

- missing storage returns an empty authoritative list;
- the repository result is newest first;
- a new repository instance reloads the same newest-first order;
- surrounding whitespace is trimmed;
- case-insensitive duplicates collapse into one entry;
- latest trimmed spelling replaces earlier spelling;
- duplicate recording moves an entry to the front;
- live-equivalent capacity removes the oldest entry;
- an injected smaller capacity behaves deterministically;
- clear removes the complete persisted list;
- isolated `UserDefaults` suites do not contaminate one another;
- corrupt payload maps to `AppError.persistence`;
- corrupt payload remains unchanged after retry;
- cancellation before a mutation is committed leaves storage unchanged;
- once the persistence API accepts a mutation, it remains committed.

Cancellation and commit-boundary tests do not depend on observing impossible
or unstable interruption points inside synchronous encoding or UserDefaults
calls. A controlled repository seam or injected persistence adapter is used
where needed to prove the boundary deterministically. Production code contains
no test-only hooks.

### SearchViewModel coverage

Tests verify:

- history loads once despite duplicate lifecycle triggers;
- load success exposes authoritative newest-first entries;
- load failure is independent from primary Search state;
- non-empty successful initial search records its query;
- empty successful initial search records its query;
- network, server, decoding, cancellation, and stale responses do not record;
- the successful-flow query reaches the repository without ViewModel
  persistence normalization;
- automatic record failure preserves primary results and prior history;
- tapping an entry starts immediately without typing debounce;
- a tapped entry moves to the front only after accepted Search success;
- typing hides history without filtering it;
- clear preserves entries until repository success;
- clear failure preserves entries;
- Retry enqueues only the exposed failed operation;
- accepted repository operations execute in FIFO order;
- resulting authoritative history matches the accepted operation sequence;
- failure does not block operations accepted afterward;
- later authoritative success replaces obsolete failure;
- cancellation prevents later presentation updates and discards queued work.

FIFO tests assert observable repository invocation order and authoritative
results, not the internal queue representation.

### Visibility coverage

The history area is eligible only when:

- query is empty;
- primary Search state is idle; and
- history has entries, is loading, or has a visible error.

Tests also verify:

- empty successful history preserves the existing idle fallback;
- updating state is visible only with entries or meaningful inline progress;
- history remains hidden during primary loading, results, empty-results, and
  failure.

### Cleanup

Every controlled operation is completed or cancelled. Test cleanup asserts
that active operations, queued operations, waiters, and stored continuations
return to zero.

Existing Search, pagination, cancellation, stale-response, Favorites, Details,
cache, networking, and persistence regression tests remain present.

## Accessibility

- `Recent Searches` is exposed as a section header.
- Each history entry is a Button with a minimum 44-point target.
- Each entry has an explicit label such as `Search for Swift`.
- Each entry has a hint explaining that it starts a repository search.
- `Clear` has a label and hint describing deletion of all recent searches.
- Inline error text and Retry remain independently accessible.
- Progress labels describe the actual operation:
  - `Loading recent searches`;
  - `Updating recent searches`;
  - `Clearing recent searches`.
- Rows remain accessible while visually present during record or clear work.
- Only actions that would create an invalid duplicate operation are disabled;
  the complete section is not disabled by default.
- Dynamic Type remains supported without fixed text frames.
- Meaning is not communicated by color alone.
- User-facing strings use the existing String Catalog.
- Debug previews cover loaded, loading, empty-fallback, updating, and failure
  states.

A new UI-test target is not introduced. Minimal UI smoke coverage remains in
the Engineering Backlog.

## Expected Architecture Footprint

Expected new files (indicative):

- `Domain/Models/SearchHistoryEntry.swift`
- `Domain/Repositories/SearchHistoryRepository.swift`
- `Data/Persistence/UserDefaultsSearchHistoryRepository.swift`
- `Features/Search/SearchHistoryViewState.swift`
- focused Search History persistence and SearchViewModel test files

Expected integration points:

- `Shared/AppError.swift`
- `App/AppContainer.swift`
- `ContentView.swift`
- `Features/Search/SearchViewModel.swift`
- `Features/Search/SearchView.swift`
- `App/PreviewDependencies.swift`
- `Localizable.xcstrings`

Exact file placement may change during implementation planning provided the
approved architectural ownership and dependency direction are preserved.

No new module, package dependency, global store, use-case layer, route, or ADR
is required. The feature applies existing accepted architecture decisions.

## Future Extensibility

- Another persistence implementation can replace UserDefaults through the
  Domain protocol.
- A shared observable store is considered only if another feature needs live
  history state.
- Timestamp metadata requires an explicit persisted-format migration and is
  not reserved speculatively.
- Capacity remains injected configuration.
- Persistence format may change internally without changing repository
  semantics.
- Cloud sync, analytics, suggestions, filtering, and autocomplete require
  separate future designs.

## Acceptance Criteria

### Prerequisite

- Pre-Phase 6 Engineering Hardening is completed and approved before Phase 6
  implementation starts.

### Functional

- History persists across repository and application recreation.
- Live capacity is 10 and remains injectable.
- Repository results and reloaded persisted history are newest first.
- Successful non-empty and empty initial searches are recorded.
- Failed, cancelled, and stale initial searches are not recorded.
- Repository recording trims surrounding whitespace.
- Duplicate matching is case-insensitive.
- Latest trimmed spelling is preserved.
- Recording a duplicate moves it to the front.
- Capacity overflow removes oldest entries from the end.
- History visibility follows the approved query, Search-state, and history-state
  rules.
- Empty successfully loaded history preserves the existing idle fallback.
- Typing hides history immediately without filtering.
- Selecting an entry fills the query and starts without typing debounce.
- Clear removes all history without confirmation.
- Clear preserves UI entries until persistence success.
- Retry repeats only the exposed failed operation.

### Architecture

- Domain owns the repository abstraction and `SearchHistoryEntry`.
- Data owns persistence implementation and raw-error mapping.
- Presentation owns history UI state and coordination.
- Dependency direction remains unchanged.
- Repository mutation owns normalization, duplicate handling, ordering,
  capacity, and atomic read-modify-write behavior.
- SearchViewModel does not normalize persistence input or access persistence.
- AppContainer owns live construction and capacity configuration.
- Search History error state remains independent.
- Cancellation remains distinct from `AppError.persistence`.
- No global store, use-case layer, route, dependency, or speculative
  abstraction is introduced.

### State and concurrency

- Only SearchViewModel accepts and manages history operations on `MainActor`.
- Operations are accepted when appended to the FIFO.
- At most one repository operation is active.
- Accepted operations execute FIFO.
- Resulting authoritative state matches the accepted operation sequence.
- Active items are removed before the next starts after success, failure, or
  cancellation.
- Failure does not block later accepted work.
- Retry enqueues exactly one new failed-operation instance.
- Load and record use repository-returned authoritative lists.
- Clear makes the empty list authoritative only after success.
- Later authoritative success replaces obsolete failure.
- After ViewModel cancellation, no later history presentation updates occur.
- ViewModel cancellation discards queued operations.
- A repository mutation completed before cancellation was observed remains
  authoritative in persistence.
- Correctness does not depend on rolling back accepted UserDefaults mutation.
- Internal queue representation may change without changing these guarantees.

### Error handling

- Load, record, and clear failures preserve appropriate authoritative entries.
- History errors do not replace primary Search results or errors.
- Automatic record failure does not change successful result presentation.
- Corrupt data maps to `AppError.persistence`.
- Corrupt-data retry does not modify stored data before retry.
- Cancellation is not rendered as a history error.

### Tests and accessibility

- New concurrency correctness tests use controlled operations, not fixed
  delays.
- FIFO tests assert observable ordering and authoritative results.
- Commit-boundary tests use deterministic seams where required.
- Controlled test cleanup returns all outstanding work to zero.
- Existing regression tests remain.
- Recent Searches, rows, Clear, Retry, and progress states have meaningful
  accessibility labels and hints.
- Visible rows remain accessible during persistence work.
- Only invalid duplicate actions are disabled.
- Dynamic Type and minimum tap targets remain supported.
- User-facing strings use the String Catalog.

### Validation

Validation applies to artifacts introduced or modified by the approved Phase 6
implementation. Existing unrelated technical debt is not implicitly included
unless it prevents successful validation.

Before implementation completion is reported:

- Debug build succeeds with warnings treated as errors;
- Release build succeeds with warnings treated as errors;
- the full unit suite passes with zero failures and zero skipped tests;
- static analyzer succeeds with no findings;
- `git diff --check` passes;
- no unrelated roadmap, architecture, ADR, source, or test change is included;
- nothing is staged, committed, amended, or pushed without explicit
  instruction.
