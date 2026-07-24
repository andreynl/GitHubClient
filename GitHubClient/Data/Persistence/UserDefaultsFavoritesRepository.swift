import Foundation

actor UserDefaultsFavoritesRepository: FavoritesRepository {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "com.andreynl.GitHubClient.favoriteRepositoryIDs"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func favoriteRepositoryIDs() async throws -> Set<Int> {
    loadRepositoryIDs()
  }

  func setFavorite(_ isFavorite: Bool, repositoryID: Int) async throws {
    var ids = loadRepositoryIDs()

    if isFavorite {
      ids.insert(repositoryID)
    } else {
      ids.remove(repositoryID)
    }

    let data = try JSONEncoder().encode(ids.sorted())
    defaults.set(data, forKey: key)
  }

  private func loadRepositoryIDs() -> Set<Int> {
    guard let data = defaults.data(forKey: key) else {
      return []
    }

    guard let ids = try? JSONDecoder().decode([Int].self, from: data) else {
      return []
    }

    return Set(ids)
  }
}
