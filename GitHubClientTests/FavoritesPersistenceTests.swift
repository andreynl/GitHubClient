import Foundation
import Testing

@testable import GitHubClient

@Suite("Favorites persistence")
struct FavoritesPersistenceTests {
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
