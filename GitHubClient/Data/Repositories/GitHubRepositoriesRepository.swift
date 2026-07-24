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
    } catch let error as GitHubAPIError {
      throw error.appError
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.unknown(error.localizedDescription)
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
    } catch let error as GitHubAPIError {
      throw error.appError
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.unknown(error.localizedDescription)
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
        throw GitHubAPIError.decoding("The README response is not valid UTF-8.")
      }
      return RepositoryReadme(content: content)
    } catch let error as GitHubAPIError {
      throw error.appError
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.unknown(error.localizedDescription)
    }
  }
}
