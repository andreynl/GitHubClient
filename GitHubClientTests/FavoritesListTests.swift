import Foundation
import Testing

@testable import GitHubClient

@Suite("Phase 5 favorites screen")
@MainActor
struct FavoritesListTests {
  @Test("Screen waits for favorites initialization")
  func initializationState() {
    let context = makeContext()

    #expect(context.viewModel.state == .initializing)
    context.viewModel.synchronize()
    #expect(context.viewModel.state == .initializing)
  }

  @Test("Initialized store with no IDs produces empty state")
  func emptyState() async {
    let context = makeContext()

    await context.store.load()
    context.viewModel.synchronize()

    #expect(context.viewModel.state == .empty)
    #expect(await context.repository.requestedIDs().isEmpty)
  }

  @Test("Lifecycle duplication starts one repository load")
  func duplicateLifecycleLoad() async throws {
    let context = makeContext(
      ids: [1],
      responses: [1: [.success(summary(id: 1), delay: .milliseconds(80))]]
    )
    await context.store.load()

    context.viewModel.synchronize()
    context.viewModel.synchronize()

    try await waitUntil { context.viewModel.visibleRepositories.count == 1 }
    #expect(await context.repository.requestedIDs() == [1])
  }

  @Test("Multiple favorites load concurrently and sort by full name")
  func successfulOrderedLoading() async throws {
    let context = makeContext(
      ids: [1, 2, 3],
      responses: [
        1: [.success(summary(id: 1, fullName: "zeta/one"), delay: .milliseconds(40))],
        2: [.success(summary(id: 2, fullName: "Apple/two"), delay: .milliseconds(10))],
        3: [.success(summary(id: 3, fullName: "middle/three"), delay: .milliseconds(20))],
      ]
    )
    await context.store.load()

    context.viewModel.synchronize()

    try await waitUntil { context.viewModel.visibleRepositories.count == 3 }
    #expect(
      context.viewModel.visibleRepositories.map(\.fullName)
        == ["Apple/two", "middle/three", "zeta/one"]
    )
    #expect(await context.repository.maximumConcurrentRequests() > 1)
  }

  @Test("Partial failure preserves successful repositories")
  func partialFailure() async throws {
    let context = makeContext(
      ids: [1, 2],
      responses: [
        1: [.success(summary(id: 1), delay: .zero)],
        2: [.failure(.notFound, delay: .zero)],
      ]
    )
    await context.store.load()

    context.viewModel.synchronize()

    try await waitUntil {
      context.viewModel.state
        == .loaded(repositories: [summary(id: 1)], failedCount: 1, isRefreshing: false)
    }
    #expect(context.viewModel.visibleRepositories.map(\.id) == [1])
  }

  @Test("Equivalent retries are deduplicated while active")
  func duplicateRetryIsIgnored() async throws {
    let context = makeContext(
      ids: [1, 2],
      responses: [
        1: [.success(summary(id: 1), delay: .zero)],
        2: [
          .failure(.offline, delay: .zero),
          .controlled,
        ],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil {
      context.viewModel.state
        == .loaded(repositories: [summary(id: 1)], failedCount: 1, isRefreshing: false)
    }

    context.viewModel.retry()
    await waitUntilForControlledTest {
      await context.repository.hasControlledRequest(id: 2, occurrence: 2)
    }
    context.viewModel.retry()
    context.viewModel.retry()

    #expect(await context.repository.requestedIDs().filter { $0 == 1 }.count == 1)
    #expect(await context.repository.requestedIDs().filter { $0 == 2 }.count == 2)
    #expect(await context.repository.maximumConcurrentRequests(id: 2) == 1)
    #expect(context.viewModel.visibleRepositories.map(\.id) == [1])

    let completed = await context.repository.completeControlled(
      id: 2,
      occurrence: 2,
      result: .success(summary(id: 2))
    )
    #expect(completed)
    await waitUntilForControlledTest { context.viewModel.visibleRepositories.count == 2 }

    #expect(await context.repository.requestedIDs().filter { $0 == 2 }.count == 2)
    #expect(Set(context.viewModel.visibleRepositories.map(\.id)) == [1, 2])
    await verifyControlledCleanup(context)
  }

  @Test("Complete failure is not presented as empty and retry recovers")
  func completeFailureAndRetry() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [
          .failure(.offline, delay: .zero),
          .success(summary(id: 1), delay: .zero),
        ],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil { context.viewModel.state == .failed(.offline) }

    context.viewModel.retry()

    try await waitUntil { context.viewModel.visibleRepositories.map(\.id) == [1] }
    #expect(await context.repository.requestedIDs() == [1, 1])
  }

  @Test("Removing an ID hides it immediately and stale completion cannot restore it")
  func removalRejectsStaleResult() async throws {
    let context = makeContext(
      ids: [1, 2],
      responses: [
        1: [
          .success(summary(id: 1), delay: .zero),
          .success(summary(id: 1), delay: .zero),
        ],
        2: [.controlled],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    await waitUntilForControlledTest {
      await context.repository.hasControlledRequest(id: 2, occurrence: 1)
    }

    context.viewModel.toggleFavorite(repositoryID: 2)
    context.viewModel.synchronize()
    await waitUntilForControlledTest { context.viewModel.visibleRepositories.map(\.id) == [1] }

    let completed = await context.repository.completeControlled(
      id: 2,
      occurrence: 1,
      result: .success(summary(id: 2))
    )
    #expect(completed)
    await waitUntilForControlledTest { await context.repository.activeRequestCount() == 0 }

    #expect(context.viewModel.favoriteRepositoryIDs == [1])
    #expect(context.viewModel.visibleRepositories.map(\.id) == [1])
    #expect(context.viewModel.state == .loaded(
      repositories: [summary(id: 1)],
      failedCount: 0,
      isRefreshing: false
    ))
    await verifyControlledCleanup(context)
  }

  @Test("Adding an ID supersedes an older load without losing the addition")
  func additionSupersedesOlderLoad() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [
          .controlled,
          .success(summary(id: 1), delay: .zero),
        ],
        2: [.success(summary(id: 2), delay: .zero)],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    await waitUntilForControlledTest {
      await context.repository.hasControlledRequest(id: 1, occurrence: 1)
    }

    context.viewModel.toggleFavorite(repositoryID: 2)
    context.viewModel.synchronize()

    await waitUntilForControlledTest {
      Set(context.viewModel.visibleRepositories.map(\.id)) == [1, 2]
    }

    let completed = await context.repository.completeControlled(
      id: 1,
      occurrence: 1,
      result: .success(summary(id: 1, fullName: "stale/one"))
    )
    #expect(completed)
    await waitUntilForControlledTest { await context.repository.activeRequestCount() == 0 }

    #expect(context.viewModel.visibleRepositories.map(\.fullName) == ["owner/repo-1", "owner/repo-2"])
    await verifyControlledCleanup(context)
  }

  @Test("Stale failure cannot replace newer successful content")
  func staleFailureCannotReplaceSuccess() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [
          .controlled,
          .success(summary(id: 1), delay: .zero),
        ],
        2: [.success(summary(id: 2), delay: .zero)],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    await waitUntilForControlledTest {
      await context.repository.hasControlledRequest(id: 1, occurrence: 1)
    }

    context.viewModel.toggleFavorite(repositoryID: 2)
    context.viewModel.synchronize()
    await waitUntilForControlledTest { context.viewModel.visibleRepositories.count == 2 }

    let completed = await context.repository.completeControlled(
      id: 1,
      occurrence: 1,
      result: .failure(AppError.offline)
    )
    #expect(completed)
    await waitUntilForControlledTest { await context.repository.activeRequestCount() == 0 }

    #expect(Set(context.viewModel.visibleRepositories.map(\.id)) == [1, 2])
    #expect(context.viewModel.state == .loaded(
      repositories: [summary(id: 1), summary(id: 2)],
      failedCount: 0,
      isRefreshing: false
    ))
    await verifyControlledCleanup(context)
  }

  @Test("Unchanged summaries are reused when a favorite is added")
  func unchangedSummariesAreReused() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [.success(summary(id: 1), delay: .zero)],
        2: [.success(summary(id: 2), delay: .zero)],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil { context.viewModel.visibleRepositories.map(\.id) == [1] }

    context.viewModel.toggleFavorite(repositoryID: 2)
    context.viewModel.synchronize()
    try await waitUntil {
      Set(context.viewModel.visibleRepositories.map(\.id)) == [1, 2]
    }

    #expect(await context.repository.requestedIDs().filter { $0 == 1 }.count == 1)
  }

  @Test("Failed removal rollback restores the cached row")
  func failedRemovalRollback() async throws {
    let persistence = FavoritesPersistenceFake(ids: [1], writeError: .unknown)
    let context = makeContext(
      persistence: persistence,
      responses: [1: [.success(summary(id: 1), delay: .zero)]]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil { context.viewModel.visibleRepositories.map(\.id) == [1] }

    context.viewModel.toggleFavorite(repositoryID: 1)
    #expect(context.viewModel.visibleRepositories.isEmpty)

    try await waitUntil { context.viewModel.favoriteRepositoryIDs.contains(1) }
    #expect(context.viewModel.visibleRepositories.map(\.id) == [1])
  }

  @Test("Refresh updates summaries without changing favorite membership")
  func refreshUpdatesContent() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [
          .success(summary(id: 1, fullName: "owner/old"), delay: .zero),
          .success(summary(id: 1, fullName: "owner/new"), delay: .zero),
        ],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil { context.viewModel.visibleRepositories.first?.fullName == "owner/old" }

    await context.viewModel.refresh()

    #expect(context.viewModel.visibleRepositories.first?.fullName == "owner/new")
    #expect(context.viewModel.favoriteRepositoryIDs == [1])
  }

  @Test("Partial refresh failure preserves existing content")
  func partialRefreshPreservesContent() async throws {
    let context = makeContext(
      ids: [1, 2],
      responses: [
        1: [
          .success(summary(id: 1, fullName: "owner/old"), delay: .zero),
          .failure(.offline, delay: .zero),
        ],
        2: [
          .success(summary(id: 2), delay: .zero),
          .success(summary(id: 2, fullName: "owner/updated"), delay: .zero),
        ],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil { context.viewModel.visibleRepositories.count == 2 }

    await context.viewModel.refresh()

    #expect(context.viewModel.visibleRepositories.contains { $0.fullName == "owner/old" })
    #expect(context.viewModel.visibleRepositories.contains { $0.fullName == "owner/updated" })
    guard case .loaded(_, let failedCount, _) = context.viewModel.state else {
      Issue.record("Expected loaded state")
      return
    }
    #expect(failedCount == 1)
  }

  @Test("Refresh cancellation preserves current content")
  func refreshCancellation() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [
          .success(summary(id: 1), delay: .zero),
          .success(summary(id: 1, fullName: "owner/new"), delay: .seconds(2)),
        ],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await waitUntil { context.viewModel.visibleRepositories.count == 1 }

    let refresh = Task { await context.viewModel.refresh() }
    try await Task.sleep(for: .milliseconds(20))
    context.viewModel.cancel()
    await refresh.value

    #expect(context.viewModel.visibleRepositories.map(\.fullName) == ["owner/repo-1"])
    #expect(!isFailure(context.viewModel.state))
    #expect(await context.repository.cancelledRequestCount() == 1)
  }

  @Test("Initial cancellation becomes idle without failure UI")
  func initialCancellation() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [.success(summary(id: 1), delay: .seconds(2))],
      ]
    )
    await context.store.load()
    context.viewModel.synchronize()
    try await Task.sleep(for: .milliseconds(20))

    context.viewModel.cancel()

    try await waitUntil { await context.repository.cancelledRequestCount() == 1 }
    #expect(context.viewModel.state == .idle)
  }

  @Test("Repository-reported cancellation remains non-visible")
  func repositoryReportedCancellation() async throws {
    let context = makeContext(
      ids: [1],
      responses: [
        1: [.failure(.cancelled, delay: .zero)],
      ]
    )
    await context.store.load()

    context.viewModel.synchronize()

    try await waitUntil { context.viewModel.state == .idle }
    #expect(!isFailure(context.viewModel.state))
  }

  @Test("Controlled fake rejects an unknown completion key")
  func controlledFakeRejectsUnknownCompletion() async {
    let repository = FavoritesScreenRepositoryFake(responses: [2: [.controlled]])
    let request = Task {
      try await repository.repository(id: 2)
    }
    await waitUntilForControlledTest {
      await repository.hasControlledRequest(id: 2, occurrence: 1)
    }

    let unknownCompletion = await repository.completeControlled(
      id: 2,
      occurrence: 2,
      result: .success(summary(id: 2))
    )

    #expect(!unknownCompletion)
    #expect(await repository.pendingControlledKeys().isEmpty)
    #expect(
      await repository.outstandingControlledKeys()
        == Set([RepositoryRequestKey(id: 2, occurrence: 1)])
    )
    #expect(await repository.cancelOutstandingControlledRequests() == 1)
    await #expect(throws: AppError.cancelled) {
      try await request.value
    }
    #expect(await repository.activeRequestCount(id: 2) == 0)
    await verifyControlledRepositoryCleanup(repository)
  }

  @Test("Controlled fake rejects duplicate completion")
  func controlledFakeRejectsDuplicateCompletion() async throws {
    let repository = FavoritesScreenRepositoryFake(responses: [2: [.controlled]])
    let request = Task {
      try await repository.repository(id: 2)
    }
    await waitUntilForControlledTest {
      await repository.hasControlledRequest(id: 2, occurrence: 1)
    }

    let firstCompletion = await repository.completeControlled(
      id: 2,
      occurrence: 1,
      result: .success(summary(id: 2))
    )
    let duplicateCompletion = await repository.completeControlled(
      id: 2,
      occurrence: 1,
      result: .failure(.offline)
    )

    #expect(firstCompletion)
    #expect(!duplicateCompletion)
    #expect(try await request.value == summary(id: 2))
    await verifyControlledRepositoryCleanup(repository)
  }

  @Test("Controlled fake cleanup resumes an outstanding request once")
  func controlledFakeCleanup() async {
    let repository = FavoritesScreenRepositoryFake(
      responses: [2: [.controlledWithRegistrationGate]]
    )
    let request = Task {
      try await repository.repository(id: 2)
    }
    await waitUntilForControlledTest {
      await repository.knowsControlledRequest(id: 2, occurrence: 1)
    }

    let hasRegisteredContinuation = await repository.hasControlledRequest(
      id: 2,
      occurrence: 1
    )
    #expect(!hasRegisteredContinuation)
    #expect(await repository.cancelOutstandingControlledRequests() == 1)
    #expect(await repository.cancelOutstandingControlledRequests() == 0)
    await #expect(throws: AppError.cancelled) {
      try await request.value
    }
    await verifyControlledRepositoryCleanup(repository)
  }

  @Test("Controlled fake supports completion before result continuation registration")
  func controlledFakeEarlyCompletion() async throws {
    let repository = FavoritesScreenRepositoryFake(
      responses: [2: [.controlledWithRegistrationGate]]
    )
    let request = Task {
      try await repository.repository(id: 2)
    }
    await waitUntilForControlledTest {
      await repository.knowsControlledRequest(id: 2, occurrence: 1)
    }

    let hasRegisteredContinuation = await repository.hasControlledRequest(
      id: 2,
      occurrence: 1
    )
    #expect(!hasRegisteredContinuation)
    let completion = await repository.completeControlled(
      id: 2,
      occurrence: 1,
      result: .success(summary(id: 2))
    )

    #expect(completion)
    #expect(try await request.value == summary(id: 2))
    let duplicateCompletion = await repository.completeControlled(
      id: 2,
      occurrence: 1,
      result: .failure(.offline)
    )
    #expect(!duplicateCompletion)
    await verifyControlledRepositoryCleanup(repository)
  }

  @Test("Concurrent loading never exceeds the configured bound")
  func boundedConcurrency() async throws {
    let responses = Dictionary(
      uniqueKeysWithValues: (1...10).map {
        ($0, [RepositoryResponse.success(summary(id: $0), delay: .milliseconds(30))])
      }
    )
    let context = makeContext(ids: Set(1...10), responses: responses, concurrencyLimit: 4)
    await context.store.load()

    context.viewModel.synchronize()

    try await waitUntil { context.viewModel.visibleRepositories.count == 10 }
    #expect(await context.repository.maximumConcurrentRequests() == 4)
  }

  private func makeContext(
    ids: Set<Int> = [],
    persistence: FavoritesPersistenceFake? = nil,
    responses: [Int: [RepositoryResponse]] = [:],
    concurrencyLimit: Int = 4
  ) -> FavoritesListContext {
    let persistence = persistence ?? FavoritesPersistenceFake(ids: ids)
    let store = FavoritesStore(repository: persistence)
    let repository = FavoritesScreenRepositoryFake(responses: responses)
    return FavoritesListContext(
      store: store,
      repository: repository,
      viewModel: FavoritesViewModel(
        repository: repository,
        favoritesStore: store,
        concurrencyLimit: concurrencyLimit
      )
    )
  }
}

@MainActor
private struct FavoritesListContext {
  let store: FavoritesStore
  let repository: FavoritesScreenRepositoryFake
  let viewModel: FavoritesViewModel
}

private enum RepositoryResponse: Sendable {
  case success(RepositorySummary, delay: Duration)
  case failure(AppError, delay: Duration)
  case controlled
  case controlledWithRegistrationGate
}

private enum ControlledRepositoryResult: Sendable {
  case success(RepositorySummary)
  case failure(AppError)
}

private struct RepositoryRequestKey: Hashable, Sendable {
  let id: Int
  let occurrence: Int
}

private actor FavoritesScreenRepositoryFake: RepositoriesRepository {
  private var responses: [Int: [RepositoryResponse]]
  private var calls: [Int] = []
  private var occurrences: [Int: Int] = [:]
  private var activeRequests = 0
  private var maximumActiveRequests = 0
  private var activeRequestsByID: [Int: Int] = [:]
  private var maximumActiveRequestsByID: [Int: Int] = [:]
  private var cancellations = 0
  private var knownControlledKeys: Set<RepositoryRequestKey> = []
  private var controlledContinuations: [
    RepositoryRequestKey: CheckedContinuation<RepositorySummary, any Error>
  ] = [:]
  private var registrationGateContinuations: [
    RepositoryRequestKey: CheckedContinuation<Void, Never>
  ] = [:]
  private var pendingControlledResults: [RepositoryRequestKey: ControlledRepositoryResult] = [:]
  private var completedControlledRequests: Set<RepositoryRequestKey> = []

  init(responses: [Int: [RepositoryResponse]]) {
    self.responses = responses
  }

  func repository(id: Int) async throws -> RepositorySummary {
    calls.append(id)
    occurrences[id, default: 0] += 1
    let key = RepositoryRequestKey(id: id, occurrence: occurrences[id, default: 0])
    activeRequests += 1
    maximumActiveRequests = max(maximumActiveRequests, activeRequests)
    activeRequestsByID[id, default: 0] += 1
    maximumActiveRequestsByID[id] = max(
      maximumActiveRequestsByID[id, default: 0],
      activeRequestsByID[id, default: 0]
    )
    defer {
      activeRequests -= 1
      activeRequestsByID[id, default: 0] -= 1
    }

    let response = responses[id]?.isEmpty == false
      ? responses[id]?.removeFirst()
      : nil

    do {
      switch response {
      case .success(let repository, let delay):
        try await Task.sleep(for: delay)
        return repository
      case .failure(let error, let delay):
        try await Task.sleep(for: delay)
        throw error
      case .controlled, .controlledWithRegistrationGate:
        knownControlledKeys.insert(key)
        if case .controlledWithRegistrationGate = response {
          await waitForRegistrationPermission(for: key)
        }
        return try await controlledResult(for: key)
      case nil:
        throw AppError.notFound
      }
    } catch is CancellationError {
      cancellations += 1
      throw CancellationError()
    } catch {
      throw error
    }
  }

  func requestedIDs() -> [Int] {
    calls
  }

  func maximumConcurrentRequests() -> Int {
    maximumActiveRequests
  }

  func maximumConcurrentRequests(id: Int) -> Int {
    maximumActiveRequestsByID[id, default: 0]
  }

  func activeRequestCount() -> Int {
    activeRequests
  }

  func activeRequestCount(id: Int) -> Int {
    activeRequestsByID[id, default: 0]
  }

  func cancelledRequestCount() -> Int {
    cancellations
  }

  func hasControlledRequest(id: Int, occurrence: Int) -> Bool {
    controlledContinuations[RepositoryRequestKey(id: id, occurrence: occurrence)] != nil
  }

  func knowsControlledRequest(id: Int, occurrence: Int) -> Bool {
    knownControlledKeys.contains(RepositoryRequestKey(id: id, occurrence: occurrence))
  }

  func completeControlled(
    id: Int,
    occurrence: Int,
    result: ControlledRepositoryResult
  ) -> Bool {
    let key = RepositoryRequestKey(id: id, occurrence: occurrence)
    guard
      knownControlledKeys.contains(key),
      completedControlledRequests.insert(key).inserted
    else {
      return false
    }

    if let continuation = controlledContinuations.removeValue(forKey: key) {
      resume(continuation, with: result)
    } else {
      pendingControlledResults[key] = result
    }

    registrationGateContinuations.removeValue(forKey: key)?.resume()
    return true
  }

  func cancelOutstandingControlledRequests() -> Int {
    let outstandingKeys = knownControlledKeys.subtracting(completedControlledRequests)

    for key in outstandingKeys {
      completedControlledRequests.insert(key)
      let cancellation = ControlledRepositoryResult.failure(.cancelled)
      if let continuation = controlledContinuations.removeValue(forKey: key) {
        resume(continuation, with: cancellation)
      } else {
        pendingControlledResults[key] = cancellation
      }
      registrationGateContinuations.removeValue(forKey: key)?.resume()
    }

    return outstandingKeys.count
  }

  func outstandingControlledKeys() -> Set<RepositoryRequestKey> {
    knownControlledKeys.subtracting(completedControlledRequests)
  }

  func pendingControlledKeys() -> Set<RepositoryRequestKey> {
    Set(pendingControlledResults.keys)
  }

  func storedContinuationKeys() -> Set<RepositoryRequestKey> {
    Set(controlledContinuations.keys)
  }

  func storedRegistrationGateKeys() -> Set<RepositoryRequestKey> {
    Set(registrationGateContinuations.keys)
  }

  func searchRepositories(query: String, page: Int, perPage: Int) async throws -> RepositoryPage {
    throw AppError.unknown
  }

  func repositoryDetails(owner: String, name: String) async throws -> RepositoryDetails {
    throw AppError.unknown
  }

  func repositoryReadme(owner: String, name: String) async throws -> RepositoryReadme {
    throw AppError.unknown
  }

  private func controlledResult(
    for key: RepositoryRequestKey
  ) async throws -> RepositorySummary {
    if let result = pendingControlledResults.removeValue(forKey: key) {
      return try result.get()
    }

    return try await withCheckedThrowingContinuation { continuation in
      controlledContinuations[key] = continuation
    }
  }

  private func waitForRegistrationPermission(
    for key: RepositoryRequestKey
  ) async {
    await withCheckedContinuation { continuation in
      registrationGateContinuations[key] = continuation
    }
  }

  private func resume(
    _ continuation: CheckedContinuation<RepositorySummary, any Error>,
    with result: ControlledRepositoryResult
  ) {
    switch result {
    case .success(let repository):
      continuation.resume(returning: repository)
    case .failure(let error):
      continuation.resume(throwing: error)
    }
  }
}

private extension ControlledRepositoryResult {
  func get() throws -> RepositorySummary {
    switch self {
    case .success(let repository):
      repository
    case .failure(let error):
      throw error
    }
  }
}

private actor FavoritesPersistenceFake: FavoritesRepository {
  private var ids: Set<Int>
  private let writeError: AppError?

  init(ids: Set<Int>, writeError: AppError? = nil) {
    self.ids = ids
    self.writeError = writeError
  }

  func favoriteRepositoryIDs() async throws -> Set<Int> {
    ids
  }

  func setFavorite(_ isFavorite: Bool, repositoryID: Int) async throws {
    if let writeError {
      throw writeError
    }

    if isFavorite {
      ids.insert(repositoryID)
    } else {
      ids.remove(repositoryID)
    }
  }
}

private func summary(id: Int, fullName: String? = nil) -> RepositorySummary {
  RepositorySummary(
    id: id,
    name: "repo-\(id)",
    fullName: fullName ?? "owner/repo-\(id)",
    owner: RepositoryOwner(id: 10, login: "owner", avatarURL: nil, profileURL: nil),
    description: "Description",
    starsCount: 100,
    forksCount: 5,
    language: "Swift",
    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
    repositoryURL: URL(string: "https://github.com/owner/repo-\(id)")
  )
}

@MainActor
private func waitUntil(
  timeout: Duration = .seconds(1),
  condition: @escaping @MainActor () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while !(await condition()) {
    if clock.now >= deadline {
      Issue.record("Timed out waiting for Favorites screen state")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

@MainActor
private func waitUntilForControlledTest(
  timeout: Duration = .seconds(1),
  condition: @escaping @MainActor () async -> Bool
) async {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while !(await condition()) {
    if clock.now >= deadline {
      Issue.record("Timed out waiting for controlled repository state")
      return
    }

    do {
      try await Task.sleep(for: .milliseconds(10))
    } catch {
      Issue.record("Controlled repository wait was cancelled")
      return
    }
  }
}

@MainActor
private func verifyControlledCleanup(_ context: FavoritesListContext) async {
  _ = await context.repository.cancelOutstandingControlledRequests()
  await verifyControlledRepositoryCleanup(context.repository)
}

@MainActor
private func verifyControlledRepositoryCleanup(
  _ repository: FavoritesScreenRepositoryFake
) async {
  await waitUntilForControlledTest {
    await repository.activeRequestCount() == 0
  }
  #expect(await repository.activeRequestCount() == 0)
  #expect(await repository.outstandingControlledKeys().isEmpty)
  #expect(await repository.pendingControlledKeys().isEmpty)
  #expect(await repository.storedContinuationKeys().isEmpty)
  #expect(await repository.storedRegistrationGateKeys().isEmpty)
}

private func isFailure(_ state: FavoritesViewState) -> Bool {
  if case .failed = state {
    return true
  }
  return false
}
