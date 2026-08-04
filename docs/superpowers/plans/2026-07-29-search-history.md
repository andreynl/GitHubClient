# Phase 6 — Search History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent, newest-first Search History to the existing Search
screen while keeping history state and failures independent from GitHub Search.

**Architecture:** Domain owns an immutable `SearchHistoryEntry` and the
`SearchHistoryRepository` abstraction. An actor-isolated UserDefaults
implementation owns atomic normalization, deduplication, ordering, capacity,
and persistence; the MainActor-isolated `SearchViewModel` owns independent
presentation state and FIFO coordination. `AppContainer` supplies the live
repository and `SearchView` renders history only inside the existing idle
Search experience.

**Tech Stack:** Swift, SwiftUI, Observation, Swift Concurrency, Foundation
`UserDefaults`, JSON encoding, Swift Testing, Xcode project file-system
synchronized groups.

## Global Constraints

- Complete and approve the mandatory Pre-Phase 6 Engineering Hardening work
  before implementation begins.
- Record only accepted, non-cancelled successful initial searches, including
  successful empty results.
- Do not record failed, cancelled, paginated, or stale Search responses.
- Trim surrounding whitespace, compare duplicates case-insensitively, and
  preserve the latest trimmed display spelling.
- Persist newest-first order and use an injected capacity of 10 in live
  composition.
- Keep GitHub Search state and Search History state independent.
- Show history only when the query is empty and primary Search is idle.
- Do not add autocomplete, suggestions, filtering while typing, recent
  repositories, analytics, cloud sync, navigation, a global history store, a
  use-case layer, a module, a dependency, or a UI-test target.
- Data maps storage, encoding, decoding, and persisted-shape failures to
  `AppError.persistence`; cancellation remains non-visible and distinct.
- Corrupt persisted data fails explicitly and is not deleted, migrated,
  quarantined, overwritten, or silently replaced.
- Only `SearchViewModel` accepts and executes history operations in FIFO order.
- Once UserDefaults accepts a mutation, treat it as committed; ViewModel
  cancellation may discard presentation results but must not roll persistence
  back.
- Use controlled fakes, checked continuations, and operation gates for new
  concurrency tests. Do not use `Task.sleep` to define correctness.
- Preserve all existing Search, pagination, Favorites, Details, cache,
  networking, persistence, cancellation, and stale-response regression tests.
- Use 2-space Swift indentation, avoid force unwraps and force casts, and keep
  user-facing strings in `Localizable.xcstrings`.
- Modify only artifacts required by the approved Phase 6 specification.
- Do not stage, commit, amend, or push without a later explicit instruction.
- Stop after each task for independent diff review and approval.

## Planned File Map

### New production files

- `GitHubClient/Domain/Models/SearchHistoryEntry.swift` — immutable Domain
  display-query value.
- `GitHubClient/Domain/Repositories/SearchHistoryRepository.swift` — Sendable
  async Domain persistence contract.
- `GitHubClient/Data/Persistence/UserDefaultsSearchHistoryRepository.swift` —
  actor-isolated atomic history rules and UserDefaults persistence.
- `GitHubClient/Features/Search/SearchHistoryViewState.swift` — independent
  history presentation state and retry-operation metadata.

### New test files

- `GitHubClientTests/SearchHistoryPersistenceTests.swift` — persistence,
  normalization, capacity, corruption, and commit-boundary coverage.
- `GitHubClientTests/SearchHistoryViewModelTests.swift` — load, record, clear,
  retry, FIFO, cancellation, stale ownership, and visibility coverage.
- `GitHubClientTests/SearchHistoryTestSupport.swift` — controlled Domain fake,
  checked-continuation gates, invocation log, and cleanup assertions.

### Existing integration files

- `GitHubClient/Shared/AppError.swift` — stable persistence error case/message.
- `GitHubClient/App/AppContainer.swift` — live repository and capacity 10.
- `GitHubClient/ContentView.swift` — inject history repository into Search.
- `GitHubClient/Features/Search/SearchViewModel.swift` — history lifecycle,
  FIFO ownership, and accepted-search recording.
- `GitHubClient/Features/Search/SearchView.swift` — idle history UI,
  accessibility, actions, and operation progress.
- `GitHubClient/App/PreviewDependencies.swift` — in-memory preview repository.
- `GitHubClient/Localizable.xcstrings` — visible and accessibility copy.

Exact file placement may change during implementation provided Domain still
owns the model/protocol, Data owns persistence, Presentation owns UI state, and
dependency direction remains unchanged.

## Shared Validation Commands

Resolve an available iPhone simulator once per execution session:

```bash
SIMULATOR_UDID="$(
  xcrun simctl list devices available -j |
    ruby -rjson -e '
      devices = JSON.parse(STDIN.read).fetch("devices")
      candidates = devices.flat_map do |runtime, entries|
        match = runtime.match(/iOS-(\d+)-(\d+)/)
        version = match ? [match[1].to_i, match[2].to_i] : [0, 0]
        entries.filter_map do |device|
          next unless device["isAvailable"] &&
            device["name"].start_with?("iPhone")
          [version, device["name"], device["udid"]]
        end
      end
      selected = candidates.sort_by {
        |version, name, _| [-version[0], -version[1], name]
      }.first
      abort("No available iPhone simulator found") unless selected
      puts selected[2]
    '
)"
test -n "$SIMULATOR_UDID"
```

Use a task-specific DerivedData directory for focused tests:

```bash
xcodebuild -quiet \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/GitHubClientPhase6TaskN \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  -only-testing:GitHubClientTests/SuiteName \
  test
```

At every review gate run:

```bash
git diff --check
git status --short --branch
git diff --cached --name-only
```

Expected: no whitespace errors, only approved Phase 6 files plus previously
known user changes are present, and nothing is staged.

---

### Task 1: Establish the Domain and AppError contracts

**Files:**

- Create: `GitHubClient/Domain/Models/SearchHistoryEntry.swift`
- Create: `GitHubClient/Domain/Repositories/SearchHistoryRepository.swift`
- Create: `GitHubClient/Features/Search/SearchHistoryViewState.swift`
- Modify: `GitHubClient/Shared/AppError.swift`
- Test: `GitHubClientTests/SearchHistoryPersistenceTests.swift`

**Interfaces:**

- Consumes: existing application-wide `AppError` convention.
- Produces:

```swift
nonisolated struct SearchHistoryEntry: Equatable, Sendable {
  let query: String
}

nonisolated protocol SearchHistoryRepository: Sendable {
  func loadHistory() async throws -> [SearchHistoryEntry]
  func recordSuccessfulQuery(_ query: String) async throws -> [SearchHistoryEntry]
  func clearHistory() async throws
}

nonisolated enum SearchHistoryOperation: Equatable, Sendable {
  case load
  case record(String)
  case clear
}

nonisolated enum SearchHistoryViewState: Equatable, Sendable {
  case idle
  case loading
  case loaded([SearchHistoryEntry])
  case updating([SearchHistoryEntry], SearchHistoryOperation)
  case failed([SearchHistoryEntry], AppError, SearchHistoryOperation)
}
```

- [ ] **Step 1: Write the failing contract tests**

Add tests that construct an entry, compare two equal entries, pass it across a
`@Sendable` closure, and verify the new stable error:

```swift
@Test("Search history entry preserves its display query")
func entryPreservesDisplayQuery() {
  let entry = SearchHistoryEntry(query: "SwiftUI")
  #expect(entry == SearchHistoryEntry(query: "SwiftUI"))
  #expect(entry.query == "SwiftUI")
}

@Test("Persistence error has stable user-facing copy")
func persistenceErrorMessage() {
  #expect(
    AppError.persistence.message
      == "Saved data could not be loaded or updated. Try again."
  )
}
```

- [ ] **Step 2: Run the focused suite and verify the contract is missing**

Run the shared focused-test command with
`SuiteName=SearchHistoryPersistenceTests`.

Expected: compilation fails because `SearchHistoryEntry` and
`AppError.persistence` do not exist.

- [ ] **Step 3: Add the minimal Domain model and repository protocol**

Create the exact interfaces shown above. Keep the model immutable and free of
timestamps, normalization, persistence, networking, SwiftUI, and DTO concerns.

- [ ] **Step 4: Add independent presentation state**

Create the exact operation and state enums shown above. Add computed accessors
only when they remove repeated exhaustive switching in `SearchViewModel` or
`SearchView`; any accessor must return existing entries without changing them.

- [ ] **Step 5: Add stable persistence error mapping**

Add `case persistence` to `AppError` and this switch branch:

```swift
case .persistence:
  "Saved data could not be loaded or updated. Try again."
```

- [ ] **Step 6: Run the focused tests and the review-gate commands**

Expected: the contract tests pass, existing `AppError` switches remain
exhaustive, `git diff --check` passes, and nothing is staged.

---

### Task 2: Implement atomic actor-isolated persistence

**Files:**

- Create: `GitHubClient/Data/Persistence/UserDefaultsSearchHistoryRepository.swift`
- Create: `GitHubClientTests/SearchHistoryPersistenceTests.swift`

**Interfaces:**

- Consumes: `SearchHistoryEntry`, `SearchHistoryRepository`,
  `AppError.persistence`.
- Produces:

```swift
actor UserDefaultsSearchHistoryRepository: SearchHistoryRepository {
  init(
    defaults: UserDefaults = .standard,
    key: String = "com.andreynl.GitHubClient.searchHistory",
    maximumCapacity: Int
  )
}
```

The initializer must reject or safely normalize non-positive capacity according
to one explicit invariant. Prefer `precondition(maximumCapacity > 0)` because
capacity is composition-time configuration rather than user input.

- [ ] **Step 1: Write missing-storage and persistence-round-trip tests**

Use a unique suite and key for every test:

```swift
let suiteName = "SearchHistoryPersistenceTests.\(UUID().uuidString)"
let defaults = try #require(UserDefaults(suiteName: suiteName))
defer { defaults.removePersistentDomain(forName: suiteName) }
let key = "history"
```

Verify `loadHistory()` returns `[]`, then record `"Swift"` and `"SwiftUI"`,
assert the returned order is `["SwiftUI", "Swift"]`, construct a new repository
with the same defaults/key, and assert it reloads the identical newest-first
order.

- [ ] **Step 2: Run the focused suite and verify it fails**

Expected: compilation fails because
`UserDefaultsSearchHistoryRepository` does not exist.

- [ ] **Step 3: Implement strict load and encoded persistence**

Persist `[String]` as JSON `Data`. Missing data returns `[]`; decoding failure
throws `.persistence`. Map every non-cancellation encoding, decoding, storage,
or shape failure before it leaves Data:

```swift
private func mapPersistenceError(_ error: Error) -> Error {
  if error is CancellationError || error as? AppError == .cancelled {
    return CancellationError()
  }
  return AppError.persistence
}
```

Do not use `try?`, delete corrupt bytes, or silently return an empty array for
malformed storage.

- [ ] **Step 4: Write normalization, duplicate, and capacity tests**

Cover these exact sequences:

```text
["Swift"] + " swift "        -> ["swift"]
["Swift", "Kotlin"] + "SWIFT" -> ["SWIFT", "Kotlin"]
capacity 3 + A, B, C, D       -> ["D", "C", "B"]
capacity 1 + Swift, SwiftUI   -> ["SwiftUI"]
```

For every ordering case, assert both the method result and a fresh repository
reload.

- [ ] **Step 5: Implement record as one actor-isolated read-modify-write**

Check cancellation before loading/mutation and immediately before committing.
Trim with `.whitespacesAndNewlines`, compare with
`caseInsensitiveCompare(_:) == .orderedSame`, remove the duplicate, insert the
latest trimmed spelling at index zero, trim the suffix to
`maximumCapacity`, encode, call `defaults.set`, and return the committed list.
Do not lowercase the stored value.

- [ ] **Step 6: Write clear, corruption, and unchanged-corruption tests**

Verify clear removes the key and a fresh repository loads `[]`. Seed invalid
JSON bytes, assert load and record throw `AppError.persistence`, retry the same
operation, and assert `defaults.data(forKey:)` remains byte-for-byte unchanged.

- [ ] **Step 7: Implement clear with commit semantics**

Check cancellation before mutation, call `defaults.removeObject(forKey:)`, and
return normally once the API accepts the removal. Do not add a cancellation
check after the accepted mutation.

- [ ] **Step 8: Add deterministic commit-boundary coverage**

If synchronous UserDefaults does not expose a stable pre-commit gate, introduce
a small production persistence adapter injected into the repository:

```swift
nonisolated protocol SearchHistoryPersistence: Sendable {
  func data(forKey key: String) throws -> Data?
  func set(_ data: Data, forKey key: String) throws
  func removeObject(forKey key: String) throws
}
```

Provide a UserDefaults-backed implementation in the same Data file. Use a
controlled test implementation to prove:

- cancellation released before `set` leaves bytes unchanged;
- cancellation after `set` acceptance does not roll the bytes back.

Do not add test-only hooks to the actor.

- [ ] **Step 9: Run persistence tests and the review gate**

Expected: all persistence cases pass deterministically; a fresh instance
preserves ordering; corruption is explicit and unchanged; no waiter or
continuation remains outstanding.

---

### Task 3: Add independent history lifecycle and FIFO ownership

**Files:**

- Create: `GitHubClientTests/SearchHistoryTestSupport.swift`
- Create: `GitHubClientTests/SearchHistoryViewModelTests.swift`
- Modify: `GitHubClient/Features/Search/SearchViewModel.swift`

**Interfaces:**

- Consumes: `SearchHistoryRepository`, `SearchHistoryViewState`,
  `SearchHistoryOperation`.
- Produces these presentation actions:

```swift
func loadSearchHistory()
func retrySearchHistory()
func clearSearchHistory()
func selectSearchHistoryEntry(_ entry: SearchHistoryEntry)
```

`loadSearchHistory()` is intentionally non-async so the ViewModel owns its task
and duplicate lifecycle calls can be ignored consistently.

- [ ] **Step 1: Build controlled test support**

Create an actor fake that logs `.load`, `.record(query)`, and `.clear`
invocations and suspends each call with a checked continuation until the test
explicitly resumes it. Expose async test-only methods equivalent to:

```swift
func waitForInvocationCount(_ count: Int) async
func invocations() -> [SearchHistoryOperation]
func succeedNext(with entries: [SearchHistoryEntry]) // load/record
func succeedNextClear()
func failNext(with error: AppError)
func cancelAll()
func outstandingOperationCount() -> Int
```

Use continuations or an `AsyncStream` signal for `waitForInvocationCount`; do
not poll or sleep. Cleanup must resume every stored continuation.

- [ ] **Step 2: Write failing load-once and load-state tests**

Construct `SearchViewModel` with the controlled history repository. Call
`loadSearchHistory()` twice, assert one invocation, verify `.loading`, then
resume with `[SearchHistoryEntry(query: "Swift")]` and verify
`.loaded(...)`. Add failure coverage for `.failed([], .persistence, .load)`.

- [ ] **Step 3: Add dependency, state, and queue ownership**

Extend the initializer with:

```swift
historyRepository: SearchHistoryRepository
```

Add:

```swift
private(set) var historyState: SearchHistoryViewState = .idle
@ObservationIgnored private let historyRepository: SearchHistoryRepository
@ObservationIgnored private var historyTask: Task<Void, Never>?
@ObservationIgnored private var pendingHistoryOperations: [SearchHistoryOperation] = []
@ObservationIgnored private var activeHistoryOperation: SearchHistoryOperation?
@ObservationIgnored private var didRequestHistoryLoad = false
```

Only a MainActor method may append, start, or remove operations. An operation is
accepted when appended. Start the next item only when no item is active. In a
single completion path, remove the active item before starting the next item on
success, failure, or cancellation.

- [ ] **Step 4: Implement load state transitions**

For load, preserve current entries, expose `.loading` only without entries,
invoke the repository, and make its returned list authoritative. On
`.persistence`, expose `.failed(existingEntries, error, .load)`. On
cancellation, emit no failure.

- [ ] **Step 5: Write failing FIFO and failure-continuation tests**

Accept load, record, and clear while the fake holds load. Verify only load is
invoked. Resume load, verify record starts next; fail record, verify clear
starts; complete clear, verify the authoritative list is empty and the obsolete
record failure no longer owns presentation.

Assert repository invocation order and final authoritative state, not the
private array representation.

- [ ] **Step 6: Implement non-blocking FIFO completion**

Every operation completion must:

1. apply a result only when the ViewModel-owned task is still allowed to update;
2. expose the failed operation as retry metadata when relevant;
3. clear `activeHistoryOperation`;
4. remove the accepted head operation;
5. start the next already accepted operation.

A later successful authoritative result replaces an older failure.

- [ ] **Step 7: Add cancellation and cleanup tests**

Cancel ViewModel-owned history work with one active and one queued operation.
Verify no later presentation update, no queued invocation, and zero fake
operations/continuations after cleanup. Add a case where the fake commits
before cancellation is observed: persistence remains committed, while the
ViewModel may discard the returned list.

- [ ] **Step 8: Cancel owned history work in lifecycle cleanup**

Extend `deinit` to cancel the history task and ensure queued operations are not
started after ownership ends. Persistence rollback must not be attempted.

- [ ] **Step 9: Run Search History ViewModel tests and the review gate**

Expected: lifecycle, FIFO, failure continuation, cancellation, and cleanup
tests pass without timing assumptions.

---

### Task 4: Record only accepted successful initial searches

**Files:**

- Modify: `GitHubClient/Features/Search/SearchViewModel.swift`
- Modify: `GitHubClientTests/SearchHistoryViewModelTests.swift`

**Interfaces:**

- Consumes: existing `performInitialSearch(query:requestID:)`,
  `shouldApplyResponse(query:requestID:)`, and FIFO acceptance.
- Produces: exactly one accepted `.record(query)` after an accepted successful
  initial page, whether that page is empty or non-empty.

- [ ] **Step 1: Write failing successful-result tests**

Use a controlled `RepositoriesRepository` and history fake. Cover a non-empty
page and an empty page. After the Search response is resumed and accepted,
assert:

```swift
#expect(await historyRepository.invocations() == [.record("SwiftUI")])
```

Resume history with its authoritative list and assert primary Search remains
`.loaded` or `.empty` respectively.

- [ ] **Step 2: Run the focused suite and verify no record occurs**

Expected: Search state succeeds but history invocation log remains empty.

- [ ] **Step 3: Accept record after primary response ownership succeeds**

Inside the successful initial-search branch, keep the existing stale/cancel
guard first, apply primary state, then enqueue:

```swift
enqueueHistoryOperation(.record(query))
```

Pass the successful-flow query unchanged from that point. Do not add
persistence trimming or case normalization to the ViewModel.

- [ ] **Step 4: Write failure, cancellation, and stale-response tests**

Verify no history record for:

- `.offline`, `.server(statusCode: 500)`, and `.decoding`;
- raw `CancellationError` and `AppError.cancelled`;
- an old Search response completed after a newer request identity owns state;
- pagination success.

Use controlled gates to decide completion order.

- [ ] **Step 5: Write record-failure independence tests**

Complete Search successfully, fail `.record` with `.persistence`, and assert:

- repository results or empty state remain unchanged;
- history preserves its prior authoritative entries;
- history exposes `.failed(entries, .persistence, .record(query))`;
- primary retry behavior and errors are untouched.

- [ ] **Step 6: Implement record success/failure transitions**

While record is active, use `.updating(existingEntries, .record(query))`.
Replace entries with the repository-returned authoritative list on success.
Preserve entries and expose only the history failure on error. Do not translate
raw persistence errors in the ViewModel.

- [ ] **Step 7: Run the focused suite and review gate**

Expected: only accepted successful initial requests record; stale, failed,
cancelled, and pagination paths never record.

---

### Task 5: Add tap-to-search, clear, and retry semantics

**Files:**

- Modify: `GitHubClient/Features/Search/SearchViewModel.swift`
- Modify: `GitHubClientTests/SearchHistoryViewModelTests.swift`

**Interfaces:**

- Consumes: existing Search request ownership/cancellation and history FIFO.
- Produces the four presentation actions declared in Task 3.

- [ ] **Step 1: Write failing tap-to-search tests**

Configure a long debounce duration, select `"SwiftUI"`, and use a controlled
Search repository invocation signal to prove the initial request starts without
releasing or waiting for a debounce clock. Verify the Search query is filled
immediately, existing Search/pagination work is cancelled, and request identity
advances.

- [ ] **Step 2: Implement immediate selection**

`selectSearchHistoryEntry(_:)` must assign `entry.query`, cancel Search and
pagination tasks, advance `activeRequestID`, and create the same owned initial
Search task used by retry without calling `Task.sleep`.

- [ ] **Step 3: Test movement only after accepted Search success**

While the selected Search request is pending or failed, assert history order is
unchanged. After accepted success and authoritative record completion, assert
the selected latest spelling moves to the front.

- [ ] **Step 4: Write failing clear tests**

Start with two entries. Call `clearSearchHistory()` and assert the entries stay
visible in `.updating(entries, .clear)` until the fake succeeds. Then verify
`.loaded([])`. In a failure case, verify
`.failed(entries, .persistence, .clear)` and unchanged entries.

- [ ] **Step 5: Implement clear acceptance**

Enqueue `.clear` without confirmation. Make `[]` authoritative only after
`clearHistory()` returns. Do not optimistically remove rows.

- [ ] **Step 6: Write operation-specific retry tests**

For failed load, record, and clear, call `retrySearchHistory()` and assert one
new matching operation is appended after already accepted work. Verify it does
not replay completed or unrelated queued operations and uses the current
authoritative entries.

- [ ] **Step 7: Implement retry from current failed state**

Guard for `.failed(_, _, retryOperation)` and enqueue exactly that operation as
a new FIFO item. If current state is no longer failed because a later
authoritative operation succeeded, Retry is a no-op.

- [ ] **Step 8: Run the focused suite and review gate**

Expected: tap bypasses debounce, clear is persistence-confirmed, Retry is
operation-specific, and accepted operations retain FIFO observable behavior.

---

### Task 6: Render the accessible idle Search History experience

**Files:**

- Modify: `GitHubClient/Features/Search/SearchView.swift`
- Modify: `GitHubClient/Features/Search/SearchViewModel.swift`
- Modify: `GitHubClient/Localizable.xcstrings`
- Modify: `GitHubClientTests/SearchHistoryViewModelTests.swift`

**Interfaces:**

- Consumes: `historyState`, Search query/phase, and Task 3/5 actions.
- Produces a pure presentation eligibility value:

```swift
var shouldShowSearchHistory: Bool
```

It is true only when the query is empty, primary phase is `.idle`, and history
has entries, is loading, or exposes a visible error/progress state.

- [ ] **Step 1: Write the visibility matrix tests**

Test the cross-product required by the specification:

- query empty + Search idle + entries/loading/error -> visible;
- empty successful history -> existing idle fallback;
- non-empty query -> hidden;
- primary loading/loaded/empty/failed -> hidden;
- updating with existing entries -> visible;
- updating without entries and without meaningful progress -> hidden.

- [ ] **Step 2: Implement the eligibility property**

Keep the rule in presentation coordination so the View contains no business
logic. Do not filter history when `state.query` changes.

- [ ] **Step 3: Replace only the idle branch presentation**

In `SearchView`, when primary phase is `.idle`, render Search History if
eligible; otherwise preserve the existing `ContentUnavailableView` unchanged.
The history content must use:

```swift
Section {
  // newest-first buttons and inline state
} header: {
  HStack {
    Text("Recent Searches")
    Spacer()
    Button("Clear") { viewModel.clearSearchHistory() }
  }
}
```

Render entries in repository order. Each row calls
`selectSearchHistoryEntry(_:)`. Render compact inline error text plus a Retry
button. Do not introduce another screen, filtering, or suggestions.

- [ ] **Step 4: Preserve rows and limit disabled actions during updates**

Keep visible rows accessible during record or clear work. Disable only an
action that would enqueue an invalid duplicate operation; do not disable the
whole section. Keep every row and action at least 44 points.

- [ ] **Step 5: Add exact progress and accessibility copy**

Add String Catalog entries used by code for:

```text
Recent Searches
Clear
Retry
Search for <query>
Starts a repository search
Clear all recent searches
Deletes all recent searches
Loading recent searches
Updating recent searches
Clearing recent searches
```

Expose the section header, explicit row labels/hints, Clear label/hint, inline
error, Retry, and operation-specific ProgressView labels to VoiceOver. Do not
rely on color alone.

- [ ] **Step 6: Load history from the existing Search lifecycle**

In the existing `.task`, retain favorites loading and request history loading
once:

```swift
.task {
  await viewModel.loadFavorites()
  viewModel.loadSearchHistory()
}
```

The ViewModel guard, not View lifecycle timing, prevents duplicate loads.

- [ ] **Step 7: Add focused previews without new dependencies**

Add idle history, loading, and inline-error preview states using preview
repositories supplied in Task 7. Do not add screenshots, GIFs, or a UI-test
target.

- [ ] **Step 8: Run focused tests and review the UI statically**

Expected: the visibility matrix passes, the old idle fallback remains for an
empty successful load, strings are catalogued, and every action has meaningful
accessibility semantics.

---

### Task 7: Complete composition, previews, and regression validation

**Files:**

- Modify: `GitHubClient/App/AppContainer.swift`
- Modify: `GitHubClient/ContentView.swift`
- Modify: `GitHubClient/App/PreviewDependencies.swift`
- Modify: every existing SearchViewModel construction site found by `rg`

**Interfaces:**

- Consumes: `SearchHistoryRepository` and
  `UserDefaultsSearchHistoryRepository`.
- Produces one live actor repository with injected capacity 10 and isolated
  in-memory preview behavior.

- [ ] **Step 1: Find every construction site before changing composition**

Run:

```bash
rg -n "SearchViewModel\\(|AppContainer\\(" GitHubClient GitHubClientTests
```

Record every result and update each explicitly; do not add a default concrete
repository inside `SearchViewModel`.

- [ ] **Step 2: Add the live AppContainer dependency**

Extend the container with:

```swift
let searchHistoryRepository: SearchHistoryRepository
```

Construct live history with:

```swift
UserDefaultsSearchHistoryRepository(maximumCapacity: 10)
```

Keep the concrete construction exclusively in the composition root.

- [ ] **Step 3: Inject the dependency through ContentView**

Pass `container.searchHistoryRepository` to the SearchViewModel initializer.
Do not pass it to Favorites, Details, or any View.

- [ ] **Step 4: Add an actor preview repository**

In `PreviewDependencies.swift`, add a minimal actor conformer backed by an
in-memory newest-first array. It may return configured success/failure states,
but must not access UserDefaults. Update `PreviewFactory.container()` and
`searchViewModel(response:)` to inject it.

- [ ] **Step 5: Run all focused Search History suites**

Run:

```bash
xcodebuild -quiet \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/GitHubClientPhase6Focused \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  -only-testing:GitHubClientTests/SearchHistoryPersistenceTests \
  -only-testing:GitHubClientTests/SearchHistoryViewModelTests \
  test
```

Expected: zero failed/skipped Search History tests and zero outstanding
controlled operations.

- [ ] **Step 6: Run Debug and Release builds**

```bash
xcodebuild -quiet \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/GitHubClientPhase6Debug \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  clean build

xcodebuild -quiet \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/GitHubClientPhase6Release \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  clean build
```

Expected: both configurations succeed with warnings treated as errors.

- [ ] **Step 7: Run the static analyzer**

```bash
xcodebuild -quiet \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/GitHubClientPhase6Analyze \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  clean analyze
```

Expected: analyzer succeeds without findings or warnings in modified Phase 6
artifacts.

- [ ] **Step 8: Run the complete unit suite**

```bash
xcodebuild -quiet \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/GitHubClientPhase6AllTests \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  test
```

Expected: zero failures, zero skipped tests, no regression test removed, and no
outstanding asynchronous test work.

- [ ] **Step 9: Review the complete implementation against the specification**

Run:

```bash
git diff --check
git diff --stat
git diff -- GitHubClient GitHubClientTests
git status --short --branch
git diff --cached --name-only
```

Confirm:

- only approved Phase 6 artifacts are added or modified by this implementation;
- Domain/Data/Presentation ownership and dependency direction remain intact;
- live capacity is exactly 10;
- no unsupported scope, dependency, route, store, module, or UI-test target was
  introduced;
- no source or test file is staged, committed, amended, or pushed.

- [ ] **Step 10: Stop for Architecture Review**

Report the AGENTS.md implementation handoff: summary, architecture impact,
files changed, behavior, tests added, validation evidence, and git status.
Request Architecture Review before Test Review or any commit authorization.
