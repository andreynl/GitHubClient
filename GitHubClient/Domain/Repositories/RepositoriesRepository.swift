nonisolated protocol RepositoriesRepository: Sendable {
  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage

  func repositoryDetails(
    owner: String,
    name: String
  ) async throws -> RepositoryDetails

  func repositoryReadme(
    owner: String,
    name: String
  ) async throws -> RepositoryReadme
}
