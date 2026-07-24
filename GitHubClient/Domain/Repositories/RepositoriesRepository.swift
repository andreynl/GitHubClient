nonisolated protocol RepositoriesRepository: Sendable {
  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage
}
