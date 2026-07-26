import Foundation
import Testing

@testable import GitHubClient

@Suite("Favorites store")
struct FavoritesStoreTests {
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
