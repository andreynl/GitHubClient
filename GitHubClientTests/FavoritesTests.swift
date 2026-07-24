import Foundation
import Testing

@testable import GitHubClient

@Suite("Phase 4 persistent favorites")
struct FavoritesTests {
  @Test("Missing storage returns an empty set")
  func missingStorage() async throws {
    let context = try UserDefaultsContext()

    #expect(try await context.repository.favoriteRepositoryIDs().isEmpty)
  }

  @Test("Favorites persist additions removals and multiple unique IDs")
  func persistenceRoundTrip() async throws {
    let context = try UserDefaultsContext()

    try await context.repository.setFavorite(true, repositoryID: 2)
    try await context.repository.setFavorite(true, repositoryID: 1)
    try await context.repository.setFavorite(true, repositoryID: 2)
    let reloadedRepository = UserDefaultsFavoritesRepository(defaults: context.defaults)
    #expect(try await reloadedRepository.favoriteRepositoryIDs() == [1, 2])

    try await reloadedRepository.setFavorite(false, repositoryID: 1)
    let repositoryAfterRemoval = UserDefaultsFavoritesRepository(defaults: context.defaults)
    #expect(try await repositoryAfterRemoval.favoriteRepositoryIDs() == [2])
  }

  @Test("Corrupt storage safely returns an empty set")
  func corruptStorage() async throws {
    let context = try UserDefaultsContext()
    context.defaults.set(
      Data("not-json".utf8),
      forKey: "com.andreynl.GitHubClient.favoriteRepositoryIDs"
    )

    #expect(try await context.repository.favoriteRepositoryIDs().isEmpty)
  }

  @Test("Injected persistent stores remain isolated")
  func persistentStoreIsolation() async throws {
    let first = try UserDefaultsContext()
    let second = try UserDefaultsContext()

    try await first.repository.setFavorite(true, repositoryID: 1)

    #expect(try await first.repository.favoriteRepositoryIDs() == [1])
    #expect(try await second.repository.favoriteRepositoryIDs().isEmpty)
  }

  @Test("Concurrent writes preserve favorites for different repositories")
  func concurrentPersistentWrites() async throws {
    let context = try UserDefaultsContext()

    async let first: Void = context.repository.setFavorite(true, repositoryID: 1)
    async let second: Void = context.repository.setFavorite(true, repositoryID: 2)
    _ = try await (first, second)

    #expect(try await context.repository.favoriteRepositoryIDs() == [1, 2])
  }

  @MainActor
  @Test("Store starts unavailable and ignores toggles before loading")
  func preLoadToggleIsIgnored() async {
    let repository = InMemoryFavoritesRepository()
    let store = FavoritesStore(repository: repository)

    #expect(!store.isLoaded)
    store.toggle(repositoryID: 1)

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(!store.isUpdating(repositoryID: 1))
    #expect(await repository.writeCalls().isEmpty)
  }

  @MainActor
  @Test("Suspended initial read keeps store unavailable until persisted IDs load")
  func suspendedInitialRead() async throws {
    let repository = InMemoryFavoritesRepository(
      ids: [1],
      readBehavior: .success(delay: .milliseconds(80))
    )
    let store = FavoritesStore(repository: repository)
    let loadTask = Task {
      await store.load()
    }

    try await waitForAsync { await repository.readCount() == 1 }
    #expect(!store.isLoaded)
    store.toggle(repositoryID: 2)
    #expect(await repository.writeCalls().isEmpty)

    await loadTask.value
    #expect(store.isLoaded)
    #expect(store.favoriteRepositoryIDs == [1])
  }

  @MainActor
  @Test("Initial read failure and cancellation resolve to loaded empty state")
  func initialReadFailureAndCancellation() async {
    let failureStore = FavoritesStore(
      repository: InMemoryFavoritesRepository(readBehavior: .failure)
    )
    let cancellationStore = FavoritesStore(
      repository: InMemoryFavoritesRepository(readBehavior: .cancellation)
    )

    await failureStore.load()
    await cancellationStore.load()

    #expect(failureStore.isLoaded)
    #expect(failureStore.favoriteRepositoryIDs.isEmpty)
    #expect(cancellationStore.isLoaded)
    #expect(cancellationStore.favoriteRepositoryIDs.isEmpty)
  }

  @MainActor
  @Test("Repeated loading performs one read and cannot overwrite later state")
  func repeatedLoading() async throws {
    let repository = InMemoryFavoritesRepository(
      ids: [1],
      readBehavior: .success(delay: .milliseconds(60))
    )
    let store = FavoritesStore(repository: repository)

    async let firstLoad: Void = store.load()
    async let secondLoad: Void = store.load()
    _ = await (firstLoad, secondLoad)

    #expect(store.isLoaded)
    #expect(await repository.readCount() == 1)

    store.toggle(repositoryID: 1)
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }
    await store.load()

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(await repository.readCount() == 1)
  }

  @MainActor
  @Test("Store loads and toggles persisted favorites")
  func storeLoadingAndToggling() async throws {
    let repository = InMemoryFavoritesRepository(ids: [1])
    let store = FavoritesStore(repository: repository)

    await store.load()
    #expect(store.favoriteRepositoryIDs == [1])

    store.toggle(repositoryID: 2)
    #expect(store.isFavorite(repositoryID: 2))
    try await waitForFavorites { !store.isUpdating(repositoryID: 2) }

    store.toggle(repositoryID: 1)
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }
    #expect(store.favoriteRepositoryIDs == [2])
    #expect(try await repository.favoriteRepositoryIDs() == [2])
  }

  @MainActor
  @Test("Search and details share favorite changes without network reloads")
  func sharedViewModelState() async throws {
    let favoritesRepository = InMemoryFavoritesRepository()
    let store = FavoritesStore(repository: favoritesRepository)
    let repositoriesRepository = FavoritesRepositoriesStub()
    let searchViewModel = SearchViewModel(
      repository: repositoriesRepository,
      favoritesStore: store,
      debounceDuration: .milliseconds(1)
    )
    let detailsViewModel = RepositoryDetailsViewModel(
      owner: "apple",
      name: "swift",
      repository: repositoriesRepository,
      favoritesStore: store
    )

    await searchViewModel.loadFavorites()
    searchViewModel.toggleFavorite(repositoryID: 1)
    try await waitForFavorites { detailsViewModel.isFavorite(repositoryID: 1) }

    detailsViewModel.toggleFavorite(repositoryID: 1)
    try await waitForFavorites { !searchViewModel.isFavorite(repositoryID: 1) }
    #expect(repositoriesRepository.callCount == 0)
  }

  @MainActor
  @Test("Write failure and cancellation roll optimistic state back")
  func writeFailureAndCancellationRollback() async throws {
    let failureRepository = InMemoryFavoritesRepository(
      writeBehaviors: [1: [.failure()]]
    )
    let cancellationRepository = InMemoryFavoritesRepository(
      writeBehaviors: [1: [.cancellation()]]
    )
    let failureStore = FavoritesStore(repository: failureRepository)
    let cancellationStore = FavoritesStore(repository: cancellationRepository)
    await failureStore.load()
    await cancellationStore.load()

    failureStore.toggle(repositoryID: 1)
    cancellationStore.toggle(repositoryID: 1)
    try await waitForFavorites {
      !failureStore.isUpdating(repositoryID: 1)
        && !cancellationStore.isUpdating(repositoryID: 1)
    }

    #expect(!failureStore.isFavorite(repositoryID: 1))
    #expect(!cancellationStore.isFavorite(repositoryID: 1))
  }

  @MainActor
  @Test("Successful favorite followed by failed removal rolls back to favorite")
  func successfulAddFailedRemoval() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [
        1: [
          .success(delay: .milliseconds(60)),
          .failure(),
        ]
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 1 }
    store.toggle(repositoryID: 1)
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }

    #expect(store.isFavorite(repositoryID: 1))
    #expect(try await repository.favoriteRepositoryIDs() == [1])
  }

  @MainActor
  @Test("Successful removal followed by failed add rolls back to not favorite")
  func successfulRemovalFailedAdd() async throws {
    let repository = InMemoryFavoritesRepository(
      ids: [1],
      writeBehaviors: [
        1: [
          .success(delay: .milliseconds(60)),
          .failure(),
        ]
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 1 }
    store.toggle(repositoryID: 1)
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(try await repository.favoriteRepositoryIDs().isEmpty)
  }

  @MainActor
  @Test("Stale failure preserves newer intent and saving state")
  func staleFailure() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [
        1: [
          .failure(delay: .milliseconds(60)),
          .success(delay: .milliseconds(80)),
        ]
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 1 }
    store.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 2 }

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(store.isUpdating(repositoryID: 1))
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }
    #expect(!store.isFavorite(repositoryID: 1))
  }

  @MainActor
  @Test("Failure for one repository does not affect another")
  func independentFailure() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [
        1: [.failure(delay: .milliseconds(60))],
        2: [.success()],
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    store.toggle(repositoryID: 2)
    try await waitForFavorites {
      !store.isUpdating(repositoryID: 1)
        && !store.isUpdating(repositoryID: 2)
    }

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(store.isFavorite(repositoryID: 2))
  }

  @MainActor
  @Test("Rapid toggles serialize writes and converge to final intent")
  func rapidToggleFinalIntent() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [
        1: [
          .success(delay: .milliseconds(60)),
          .success(delay: .milliseconds(40)),
        ]
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 1 }
    store.toggle(repositoryID: 1)
    store.toggle(repositoryID: 1)
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }

    #expect(store.isFavorite(repositoryID: 1))
    #expect(await repository.writeCalls().map(\.isFavorite) == [true, true])
    #expect(await repository.maximumConcurrentWrites(for: 1) == 1)
  }

  @MainActor
  @Test("One repository write does not block another repository")
  func independentRepositoryWrites() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [
        1: [.success(delay: .milliseconds(100))],
        2: [.success()],
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    store.toggle(repositoryID: 2)
    try await waitForFavorites {
      store.isFavorite(repositoryID: 2)
        && !store.isUpdating(repositoryID: 2)
    }

    #expect(store.isUpdating(repositoryID: 1))
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }
  }

  @MainActor
  @Test("Suspended write does not retain store and is cancelled on deinit")
  func suspendedWriteLifecycle() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [1: [.suspendUntilCancelled]]
    )
    var store: FavoritesStore? = FavoritesStore(repository: repository)
    await store?.load()
    let weakStore = WeakReference(store)

    store?.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 1 }
    store = nil

    try await waitForFavorites { weakStore.value == nil }
    try await waitForAsync { await repository.cancelledWriteCount() == 1 }
  }
}

private final class WeakReference<Value: AnyObject> {
  weak var value: Value?

  init(_ value: Value?) {
    self.value = value
  }
}

private final class UserDefaultsContext {
  let defaults: UserDefaults
  let repository: UserDefaultsFavoritesRepository

  private let suiteName: String

  init() throws {
    suiteName = "GitHubClientTests.Favorites.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    repository = UserDefaultsFavoritesRepository(defaults: defaults)
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

enum FavoriteTestError: Error, Sendable {
  case failure
}

enum FavoriteReadBehavior: Sendable {
  case success(delay: Duration = .zero)
  case failure
  case cancellation
}

enum FavoriteWriteBehavior: Sendable {
  case success(delay: Duration = .zero)
  case failure(delay: Duration = .zero)
  case cancellation(delay: Duration = .zero)
  case suspendUntilCancelled
}

struct FavoriteWriteCall: Equatable, Sendable {
  let repositoryID: Int
  let isFavorite: Bool
}

actor InMemoryFavoritesRepository: FavoritesRepository {
  private var ids: Set<Int>
  private let readBehavior: FavoriteReadBehavior
  private var writeBehaviors: [Int: [FavoriteWriteBehavior]]
  private var reads = 0
  private var calls: [FavoriteWriteCall] = []
  private var activeWrites: [Int: Int] = [:]
  private var maximumWrites: [Int: Int] = [:]
  private var cancelledWrites = 0

  init(
    ids: Set<Int> = [],
    readBehavior: FavoriteReadBehavior = .success(),
    writeBehaviors: [Int: [FavoriteWriteBehavior]] = [:]
  ) {
    self.ids = ids
    self.readBehavior = readBehavior
    self.writeBehaviors = writeBehaviors
  }

  func favoriteRepositoryIDs() async throws -> Set<Int> {
    reads += 1

    switch readBehavior {
    case .success(let delay):
      try await Task.sleep(for: delay)
      return ids
    case .failure:
      throw FavoriteTestError.failure
    case .cancellation:
      throw CancellationError()
    }
  }

  func setFavorite(_ isFavorite: Bool, repositoryID: Int) async throws {
    let call = FavoriteWriteCall(repositoryID: repositoryID, isFavorite: isFavorite)
    calls.append(call)
    activeWrites[repositoryID, default: 0] += 1
    maximumWrites[repositoryID] = max(
      maximumWrites[repositoryID, default: 0],
      activeWrites[repositoryID, default: 0]
    )
    defer {
      activeWrites[repositoryID, default: 0] -= 1
    }

    let behavior = nextWriteBehavior(repositoryID: repositoryID)
    switch behavior {
    case .success(let delay):
      try await Task.sleep(for: delay)
      setPersistedValue(isFavorite, repositoryID: repositoryID)
    case .failure(let delay):
      try await Task.sleep(for: delay)
      throw FavoriteTestError.failure
    case .cancellation(let delay):
      try await Task.sleep(for: delay)
      throw CancellationError()
    case .suspendUntilCancelled:
      do {
        try await Task.sleep(for: .seconds(3_600))
      } catch is CancellationError {
        cancelledWrites += 1
        throw CancellationError()
      }
    }
  }

  func readCount() -> Int {
    reads
  }

  func writeCalls() -> [FavoriteWriteCall] {
    calls
  }

  func maximumConcurrentWrites(for repositoryID: Int) -> Int {
    maximumWrites[repositoryID, default: 0]
  }

  func cancelledWriteCount() -> Int {
    cancelledWrites
  }

  private func nextWriteBehavior(repositoryID: Int) -> FavoriteWriteBehavior {
    guard var behaviors = writeBehaviors[repositoryID], !behaviors.isEmpty else {
      return .success()
    }

    let behavior = behaviors.removeFirst()
    writeBehaviors[repositoryID] = behaviors
    return behavior
  }

  private func setPersistedValue(_ isFavorite: Bool, repositoryID: Int) {
    if isFavorite {
      ids.insert(repositoryID)
    } else {
      ids.remove(repositoryID)
    }
  }
}

@MainActor
func makeFavoritesStore(ids: Set<Int> = []) -> FavoritesStore {
  FavoritesStore(repository: InMemoryFavoritesRepository(ids: ids))
}

private final class FavoritesRepositoriesStub: RepositoriesRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0

  var callCount: Int {
    lock.withLock { calls }
  }

  func searchRepositories(query: String, page: Int, perPage: Int) async throws -> RepositoryPage {
    lock.withLock {
      calls += 1
    }
    return RepositoryPage(items: [], currentPage: page, hasNextPage: false, totalCount: 0)
  }

  func repositoryDetails(owner: String, name: String) async throws -> RepositoryDetails {
    lock.withLock {
      calls += 1
    }
    throw AppError.notFound
  }

  func repository(id: Int) async throws -> RepositorySummary {
    lock.withLock {
      calls += 1
    }
    throw AppError.notFound
  }

  func repositoryReadme(owner: String, name: String) async throws -> RepositoryReadme {
    lock.withLock {
      calls += 1
    }
    throw AppError.notFound
  }
}

@MainActor
private func waitForFavorites(
  timeout: Duration = .seconds(1),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let start = ContinuousClock.now
  while !condition() {
    if ContinuousClock.now - start > timeout {
      Issue.record("Timed out waiting for favorite state")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

private func waitForAsync(
  timeout: Duration = .seconds(1),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let start = ContinuousClock.now
  while !(await condition()) {
    if ContinuousClock.now - start > timeout {
      Issue.record("Timed out waiting for asynchronous favorite condition")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}
