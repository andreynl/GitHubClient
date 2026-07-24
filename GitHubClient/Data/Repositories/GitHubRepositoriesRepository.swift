import Foundation

nonisolated final class GitHubRepositoriesRepository: RepositoriesRepository {
  private let apiClient: GitHubAPIClient
  private let searchCache: RepositorySearchMemoryCache
  private let detailsCache: RepositoryDetailsMemoryCache

  init(
    apiClient: GitHubAPIClient,
    searchCache: RepositorySearchMemoryCache = RepositorySearchMemoryCache(),
    detailsCache: RepositoryDetailsMemoryCache = RepositoryDetailsMemoryCache()
  ) {
    self.apiClient = apiClient
    self.searchCache = searchCache
    self.detailsCache = detailsCache
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

    if let cachedPage = await searchCache.value(for: key) {
      return cachedPage
    }

    do {
      let dto: RepositorySearchResponseDTO = try await apiClient.send(
        .searchRepositories(query: normalizedQuery, page: page, perPage: perPage)
      )
      let page = dto.toDomain(page: page, perPage: perPage)
      await searchCache.store(page, for: key)
      return page
    } catch {
      throw mapToAppError(error)
    }
  }

  func repositoryDetails(
    owner: String,
    name: String
  ) async throws -> RepositoryDetails {
    let normalizedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let key = RepositoryDetailsCacheKey(owner: normalizedOwner, name: normalizedName)

    if let cachedDetails = await detailsCache.value(for: key) {
      return cachedDetails
    }

    do {
      let dto: RepositoryDetailsDTO = try await apiClient.send(
        .repositoryDetails(owner: normalizedOwner, name: normalizedName)
      )
      let details = dto.toDomain()
      await detailsCache.store(details, for: key)
      return details
    } catch {
      throw mapToAppError(error)
    }
  }

  func repository(id: Int) async throws -> RepositorySummary {
    do {
      let dto: RepositoryDTO = try await apiClient.send(.repository(id: id))
      return dto.toDomain()
    } catch {
      throw mapToAppError(error)
    }
  }

  func repositoryReadme(
    owner: String,
    name: String
  ) async throws -> RepositoryReadme {
    let normalizedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      let data = try await apiClient.sendData(
        .repositoryReadme(owner: normalizedOwner, name: normalizedName)
      )
      guard let content = String(data: data, encoding: .utf8) else {
        throw GitHubAPIError.decoding(
          GitHubErrorDiagnostics(
            domain: "GitHubClient.RepositoryReadme",
            code: 1,
            debugDescription: "The README response is not valid UTF-8."
          )
        )
      }
      return RepositoryReadme(content: content)
    } catch {
      throw mapToAppError(error)
    }
  }

  private func mapToAppError(_ error: Error) -> AppError {
    if let appError = error as? AppError {
      return appError
    }

    if let apiError = error as? GitHubAPIError {
      return apiError.appError
    }

    if error is CancellationError {
      return .cancelled
    }

    return .unknown
  }
}
