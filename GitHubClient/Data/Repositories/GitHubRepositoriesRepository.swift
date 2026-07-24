import Foundation

nonisolated final class GitHubRepositoriesRepository: RepositoriesRepository {
  private let apiClient: GitHubAPIClient
  private let cache: RepositorySearchMemoryCache

  init(
    apiClient: GitHubAPIClient,
    cache: RepositorySearchMemoryCache = RepositorySearchMemoryCache()
  ) {
    self.apiClient = apiClient
    self.cache = cache
  }

  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let key = RepositorySearchCacheKey(
      query: normalizedQuery.lowercased(),
      page: page,
      perPage: perPage
    )

    if let cachedPage = await cache.value(for: key) {
      return cachedPage
    }

    do {
      let dto: RepositorySearchResponseDTO = try await apiClient.send(
        .searchRepositories(query: normalizedQuery, page: page, perPage: perPage)
      )
      let page = dto.toDomain(page: page, perPage: perPage)
      await cache.store(page, for: key)
      return page
    } catch let error as GitHubAPIError {
      throw error.appError
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.unknown(error.localizedDescription)
    }
  }
}
