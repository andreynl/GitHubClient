import Foundation
import Testing

@testable import GitHubClient

@Suite("Favorites store concurrency")
struct FavoritesStoreConcurrencyTests {
  @MainActor
  @Test("Stale failure preserves newer intent and saving state")
  func staleFailure() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [
        1: [
          .controlled,
          .controlled,
        ]
      ]
    )
    let store = FavoritesStore(repository: repository)
    await store.load()

    store.toggle(repositoryID: 1)
    try await waitForAsync { await repository.writeCalls().count == 1 }
    store.toggle(repositoryID: 1)

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(store.isUpdating(repositoryID: 1))
    #expect(
      await repository.completeNextControlledWrite(
        repositoryID: 1,
        result: .failure
      )
    )
    try await waitForAsync { await repository.writeCalls().count == 2 }

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(store.isUpdating(repositoryID: 1))
    #expect(await repository.pendingControlledWriteCount() == 1)
    #expect(
      await repository.completeNextControlledWrite(
        repositoryID: 1,
        result: .success
      )
    )
    try await waitForFavorites { !store.isUpdating(repositoryID: 1) }

    #expect(!store.isFavorite(repositoryID: 1))
    #expect(try await repository.favoriteRepositoryIDs().isEmpty)
    #expect(
      await repository.writeCalls().map(\.isFavorite) == [true, false]
    )
    #expect(await repository.maximumConcurrentWrites(for: 1) == 1)
    #expect(await repository.pendingControlledWriteCount() == 0)
  }

  @Test("Cancelling a controlled write resumes and removes its continuation")
  func controlledWriteCancellation() async throws {
    let repository = InMemoryFavoritesRepository(
      writeBehaviors: [1: [.controlled]]
    )
    let writeTask = Task {
      try await repository.setFavorite(true, repositoryID: 1)
    }

    try await waitForAsync {
      await repository.pendingControlledWriteCount() == 1
    }
    writeTask.cancel()

    do {
      try await writeTask.value
      Issue.record("Expected controlled write cancellation")
    } catch is CancellationError {
      // Expected cancellation.
    } catch {
      Issue.record("Expected CancellationError, received \(error)")
    }

    #expect(await repository.pendingControlledWriteCount() == 0)
    #expect(
      await repository.completeNextControlledWrite(
        repositoryID: 1,
        result: .success
      ) == false
    )
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
