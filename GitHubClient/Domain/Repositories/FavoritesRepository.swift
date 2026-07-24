nonisolated protocol FavoritesRepository: Sendable {
  func favoriteRepositoryIDs() async throws -> Set<Int>
  func setFavorite(_ isFavorite: Bool, repositoryID: Int) async throws
}
