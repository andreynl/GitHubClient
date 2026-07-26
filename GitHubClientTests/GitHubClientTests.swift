import Foundation
import Testing

@testable import GitHubClient

@Suite("Phase 1 repository search")
struct GitHubClientTests {
  @Test("Endpoint constructs and encodes search query")
  func endpointConstruction() throws {
    let endpoint = GitHubEndpoint.searchRepositories(query: "swift ui", page: 2, perPage: 25)
    let baseURL = try #require(URL(string: "https://api.github.com"))
    let request = try endpoint.urlRequest(baseURL: baseURL, accessToken: "token")

    #expect(request.url?.path == "/search/repositories")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "GitHubClient")
    #expect(
      request.value(forHTTPHeaderField: "X-GitHub-Api-Version")
        == GitHubEndpoint.apiVersion
    )
    #expect(GitHubEndpoint.apiVersion == "2026-03-10")

    let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
    let queryItems = try #require(components?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "q", value: "swift ui")))
    #expect(queryItems.contains(URLQueryItem(name: "page", value: "2")))
    #expect(queryItems.contains(URLQueryItem(name: "per_page", value: "25")))
  }

  @Test("Repository-by-ID endpoint constructs the canonical GitHub path")
  func repositoryByIDEndpointConstruction() throws {
    let endpoint = GitHubEndpoint.repository(id: 42)
    let baseURL = try #require(URL(string: "https://api.github.com"))
    let request = try endpoint.urlRequest(baseURL: baseURL, accessToken: nil)

    #expect(request.url?.path == "/repositories/42")
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
  }

  @Test("Repository maps repository-by-ID response into a summary")
  func repositoryByIDMapping() async throws {
    let store = MockURLProtocolStore { request in
      #expect(request.url?.path == "/repositories/42")
      return HTTPResponse(
        statusCode: 200,
        headers: [:],
        data: sampleRepositoryData(id: 42, fullName: "apple/swift")
      )
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    let result = try await repository.repository(id: 42)

    #expect(result.id == 42)
    #expect(result.fullName == "apple/swift")
  }

  @Test("DTO decodes and maps into domain")
  func dtoDecodingAndMapping() throws {
    let data = sampleSearchResponseData(totalCount: 31, id: 1, fullName: "apple/swift")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let dto = try decoder.decode(RepositorySearchResponseDTO.self, from: data)
    let page = dto.toDomain(page: 1, perPage: 30)

    #expect(page.totalCount == 31)
    #expect(page.hasNextPage)
    #expect(page.items.first?.fullName == "apple/swift")
    #expect(page.items.first?.owner.login == "apple")
    #expect(page.items.first?.starsCount == 100)
    #expect(page.items.first?.forksCount == 5)
    #expect(!page.isIncomplete)
  }

  @Test("DTO preserves GitHub incomplete search results")
  func dtoIncompleteResultMapping() throws {
    let data = sampleSearchResponseData(
      totalCount: 1,
      id: 1,
      fullName: "apple/swift",
      isIncomplete: true
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let dto = try decoder.decode(RepositorySearchResponseDTO.self, from: data)
    let page = dto.toDomain(page: 1, perPage: 30)

    #expect(page.isIncomplete)
    #expect(page.items.map(\.fullName) == ["apple/swift"])
  }

  @Test("API client decodes successful response")
  func apiClientSuccess() async throws {
    let store = MockURLProtocolStore { request in
      #expect(request.url?.path == "/search/repositories")
      return HTTPResponse(
        statusCode: 200,
        headers: [:],
        data: sampleSearchResponseData(totalCount: 1, id: 1, fullName: "apple/swift")
      )
    }
    let client = GitHubAPIClient(
      baseURL: try #require(URL(string: "https://api.github.test")),
      session: makeSession(store: store)
    )

    let dto: RepositorySearchResponseDTO = try await client.send(
      .searchRepositories(query: "swift", page: 1, perPage: 30)
    )

    #expect(dto.items.first?.fullName == "apple/swift")
  }

  @Test("API client maps HTTP errors")
  func apiClientHTTPErrorMapping() async throws {
    let store = MockURLProtocolStore { _ in
      HTTPResponse(statusCode: 500, headers: [:], data: Data())
    }
    let client = GitHubAPIClient(
      baseURL: try #require(URL(string: "https://api.github.test")),
      session: makeSession(store: store)
    )

    await #expect(throws: GitHubAPIError.server(statusCode: 500)) {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
    }
  }

  @Test("API client maps transport failures")
  func apiClientTransportFailureMapping() async throws {
    let store = MockURLProtocolStore { _ in
      throw URLError(.notConnectedToInternet)
    }
    let client = GitHubAPIClient(
      baseURL: try #require(URL(string: "https://api.github.test")),
      session: makeSession(store: store)
    )

    await #expect(throws: GitHubAPIError.offline) {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
    }
  }

  @Test("API client maps raw token-provider cancellation without starting transport")
  func apiClientRawCancellationMapping() async throws {
    let store = MockURLProtocolStore { _ in
      Issue.record("Cancellation during token acquisition must not start a request")
      return HTTPResponse(statusCode: 200, headers: [:], data: Data())
    }
    let client = GitHubAPIClient(
      baseURL: try #require(URL(string: "https://api.github.test")),
      session: makeSession(store: store),
      accessTokenProvider: CancellingAccessTokenProvider()
    )

    await #expect(throws: GitHubAPIError.cancelled) {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
    }
  }

  @Test("Repository maps raw token-provider cancellation to app cancellation")
  func repositoryRawCancellationMapping() async throws {
    let store = MockURLProtocolStore { _ in
      Issue.record("Cancellation during token acquisition must not start a request")
      return HTTPResponse(statusCode: 200, headers: [:], data: Data())
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store),
        accessTokenProvider: CancellingAccessTokenProvider()
      )
    )

    await #expect(throws: AppError.cancelled) {
      _ = try await repository.searchRepositories(query: "swift", page: 1, perPage: 30)
    }
  }

  @Test("API client preserves structured transport diagnostics")
  func apiClientTransportDiagnostics() async throws {
    let store = MockURLProtocolStore { _ in
      throw URLError(.cannotFindHost)
    }
    let client = GitHubAPIClient(
      baseURL: try #require(URL(string: "https://api.github.test")),
      session: makeSession(store: store)
    )

    do {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
      Issue.record("Expected transport error")
    } catch GitHubAPIError.transport(let diagnostics) {
      #expect(diagnostics.domain == NSURLErrorDomain)
      #expect(diagnostics.code == URLError.cannotFindHost.rawValue)
      #expect(!diagnostics.debugDescription.isEmpty)
    }
  }

  @Test("Repository maps decoding failures to stable app error")
  func repositoryDecodingErrorMapping() async throws {
    let store = MockURLProtocolStore { _ in
      HTTPResponse(statusCode: 200, headers: [:], data: Data("{".utf8))
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    await #expect(throws: AppError.decoding) {
      _ = try await repository.searchRepositories(query: "swift", page: 1, perPage: 30)
    }
  }

  @Test("Repository maps generic transport failures to stable app error")
  func repositoryTransportErrorMapping() async throws {
    let store = MockURLProtocolStore { _ in
      throw URLError(.cannotConnectToHost)
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    await #expect(throws: AppError.transport) {
      _ = try await repository.searchRepositories(query: "swift", page: 1, perPage: 30)
    }
  }

  @Test("Repository preserves offline as a distinct app error")
  func repositoryOfflineErrorMapping() async throws {
    let store = MockURLProtocolStore { _ in
      throw URLError(.notConnectedToInternet)
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    await #expect(throws: AppError.offline) {
      _ = try await repository.searchRepositories(query: "swift", page: 1, perPage: 30)
    }
  }

  @Test("API client maps rate limit headers")
  func apiClientRateLimitMapping() async throws {
    let store = MockURLProtocolStore { _ in
      HTTPResponse(
        statusCode: 403,
        headers: [
          "x-ratelimit-limit": "60",
          "x-ratelimit-remaining": "0",
          "x-ratelimit-reset": "1800000000",
        ],
        data: Data()
      )
    }
    let client = GitHubAPIClient(
      baseURL: try #require(URL(string: "https://api.github.test")),
      session: makeSession(store: store)
    )

    do {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
      Issue.record("Expected rate limit error")
    } catch GitHubAPIError.rateLimited(let info) {
      #expect(info?.limit == 60)
      #expect(info?.remaining == 0)
      #expect(info?.resetAt == Date(timeIntervalSince1970: 1_800_000_000))
      #expect(info?.retryAfterSeconds == nil)
    }
  }

  @Test("API client maps secondary rate limit response bodies")
  func apiClientSecondaryRateLimitMapping() async throws {
    let client = makeAPIClient(
      response: HTTPResponse(
        statusCode: 403,
        headers: [:],
        data: Data(#"{"message":"You have exceeded a secondary rate limit."}"#.utf8)
      )
    )

    await #expect(throws: GitHubAPIError.rateLimited(
      RateLimitInfo(limit: nil, remaining: nil, resetAt: nil)
    )) {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
    }
  }

  @Test("API client parses Retry-After on secondary rate limiting")
  func apiClientRetryAfterMapping() async throws {
    let client = makeAPIClient(
      response: HTTPResponse(
        statusCode: 403,
        headers: ["Retry-After": "120"],
        data: Data()
      )
    )

    do {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
      Issue.record("Expected rate limit error")
    } catch GitHubAPIError.rateLimited(let info) {
      #expect(info?.retryAfterSeconds == 120)
      #expect(info?.remaining == nil)
    }
  }

  @Test("API client maps 429 to rate limiting")
  func apiClientTooManyRequestsMapping() async throws {
    let client = makeAPIClient(
      response: HTTPResponse(
        statusCode: 429,
        headers: ["Retry-After": "30"],
        data: Data()
      )
    )

    do {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
      Issue.record("Expected rate limit error")
    } catch GitHubAPIError.rateLimited(let info) {
      #expect(info?.retryAfterSeconds == 30)
    }
  }

  @Test("API client preserves ordinary forbidden responses")
  func apiClientForbiddenMapping() async throws {
    let client = makeAPIClient(
      response: HTTPResponse(statusCode: 403, headers: [:], data: Data())
    )

    await #expect(throws: GitHubAPIError.forbidden) {
      let _: RepositorySearchResponseDTO = try await client.send(
        .searchRepositories(query: "swift", page: 1, perPage: 30)
      )
    }
  }

  @Test("Repository caches query and page combinations")
  func repositoryCaching() async throws {
    let counter = LockedCounter()
    let store = MockURLProtocolStore { _ in
      counter.increment()
      return HTTPResponse(
        statusCode: 200,
        headers: [:],
        data: sampleSearchResponseData(totalCount: 1, id: 1, fullName: "apple/swift")
      )
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    let first = try await repository.searchRepositories(query: "Swift", page: 1, perPage: 30)
    let second = try await repository.searchRepositories(query: " swift ", page: 1, perPage: 30)
    _ = try await repository.searchRepositories(query: "swift", page: 2, perPage: 30)

    #expect(counter.value == 2)
    #expect(first == second)
  }

  @MainActor
  @Test("Search view model loads successful results")
  func viewModelSuccess() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      RepositoryPage(items: [repositorySummary(id: page)], currentPage: page, hasNextPage: false, totalCount: 1)
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }

    #expect(viewModel.state.items.count == 1)
    #expect(viewModel.state.pagination == .endReached)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Search view model preserves incomplete results non-fatally")
  func viewModelIncompleteResults() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      RepositoryPage(
        items: [repositorySummary(id: page)],
        currentPage: page,
        hasNextPage: false,
        totalCount: 1,
        isIncomplete: true
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }

    #expect(viewModel.state.items.map(\.id) == [1])
    #expect(viewModel.state.isShowingIncompleteResults)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Search view model handles empty results")
  func viewModelEmpty() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      RepositoryPage(items: [], currentPage: page, hasNextPage: false, totalCount: 0)
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .empty }

    #expect(viewModel.state.items.isEmpty)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Search view model retries initial errors")
  func viewModelInitialErrorAndRetry() async throws {
    let repository = MockRepositoriesRepository { _, _, callCount in
      if callCount == 1 {
        throw AppError.server(statusCode: 500)
      }
      return RepositoryPage(items: [repositorySummary(id: 1)], currentPage: 1, hasNextPage: false, totalCount: 1)
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .failed }
    #expect(viewModel.state.error == .server(statusCode: 500))

    viewModel.retry()
    try await waitFor { viewModel.state.phase == .loaded }
    #expect(viewModel.state.items.count == 1)
  }

  @MainActor
  @Test("Search view model respects minimum query length")
  func viewModelMinimumQueryLength() async throws {
    let repository = MockRepositoriesRepository { _, _, _ in
      RepositoryPage(items: [repositorySummary(id: 1)], currentPage: 1, hasNextPage: false, totalCount: 1)
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      minimumQueryLength: 3,
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("sw")

    #expect(viewModel.state.phase == .idle)
    #expect(repository.callCount == 0)
  }

  @MainActor
  @Test("Search view model cancels previous debounced search")
  func viewModelCancellation() async throws {
    let repository = MockRepositoriesRepository { query, _, _ in
      RepositoryPage(
        items: [repositorySummary(id: query == "swiftui" ? 2 : 1)],
        currentPage: 1,
        hasNextPage: false,
        totalCount: 1
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(50)
    )

    viewModel.updateQuery("swift")
    viewModel.updateQuery("swiftui")
    try await waitFor { viewModel.state.phase == .loaded }

    #expect(viewModel.state.items.map(\.id) == [2])
    #expect(repository.callCount == 1)
  }

  @MainActor
  @Test("Search view model prevents stale responses")
  func viewModelStaleResponsePrevention() async throws {
    let repository = MockRepositoriesRepository { query, _, _ in
      if query == "swift" {
        do {
          try await Task.sleep(for: .milliseconds(80))
        } catch is CancellationError {
          // Deliberately return a stale result to verify request identity protection.
        }
        return RepositoryPage(
          items: [repositorySummary(id: 1, fullName: "old/result")],
          currentPage: 1,
          hasNextPage: false,
          totalCount: 1
        )
      }

      return RepositoryPage(
        items: [repositorySummary(id: 2, fullName: "new/result")],
        currentPage: 1,
        hasNextPage: false,
        totalCount: 1
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await Task.sleep(for: .milliseconds(10))
    viewModel.updateQuery("swiftui")
    try await waitFor { viewModel.state.items.map(\.id) == [2] }
    try await Task.sleep(for: .milliseconds(120))

    #expect(viewModel.state.items.map(\.id) == [2])
  }

  @MainActor
  @Test("Search repository cancellation resets the current loading state")
  func viewModelRepositoryCancellation() async throws {
    let repository = MockRepositoriesRepository { _, _, callCount in
      if callCount == 1 {
        throw AppError.cancelled
      }
      return RepositoryPage(
        items: [repositorySummary(id: 2)],
        currentPage: 1,
        hasNextPage: false,
        totalCount: 1
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { repository.callCount == 1 && viewModel.state.phase == .idle }

    #expect(viewModel.state.error == nil)
    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.items.map(\.id) == [2] }
  }

  @MainActor
  @Test("Stale search cancellation does not overwrite a newer request")
  func viewModelStaleCancellation() async throws {
    let repository = MockRepositoriesRepository { query, _, _ in
      if query == "swift" {
        do {
          try await Task.sleep(for: .milliseconds(80))
        } catch is CancellationError {
          throw AppError.cancelled
        }
      }
      return RepositoryPage(
        items: [repositorySummary(id: 2)],
        currentPage: 1,
        hasNextPage: false,
        totalCount: 1
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { repository.callCount == 1 }
    viewModel.updateQuery("swiftui")
    try await waitFor { viewModel.state.items.map(\.id) == [2] }
    try await Task.sleep(for: .milliseconds(100))

    #expect(viewModel.state.phase == .loaded)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Search view model paginates")
  func viewModelPagination() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      RepositoryPage(
        items: [repositorySummary(id: page)],
        currentPage: page,
        hasNextPage: page < 2,
        totalCount: 2
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }
    viewModel.loadNextPage()
    try await waitFor { viewModel.state.items.count == 2 }

    #expect(viewModel.state.items.map(\.id) == [1, 2])
    #expect(viewModel.state.pagination == .endReached)
  }

  @MainActor
  @Test("Search view model prevents duplicate page loads")
  func viewModelDuplicatePagePrevention() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      if page == 2 {
        try await Task.sleep(for: .milliseconds(80))
      }
      return RepositoryPage(
        items: [repositorySummary(id: page)],
        currentPage: page,
        hasNextPage: page < 2,
        totalCount: 2
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }
    viewModel.loadNextPage()
    viewModel.loadNextPage()
    try await waitFor { viewModel.state.items.count == 2 }

    #expect(repository.calls.filter { $0.page == 2 }.count == 1)
  }

  @MainActor
  @Test("Pagination failure preserves current items")
  func viewModelPaginationFailurePreservesItems() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      if page == 2 {
        throw AppError.rateLimited(RateLimitInfo(limit: 60, remaining: 0, resetAt: nil))
      }
      return RepositoryPage(items: [repositorySummary(id: 1)], currentPage: 1, hasNextPage: true, totalCount: 2)
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }
    viewModel.loadNextPage()
    try await waitFor {
      if case .failed = viewModel.state.pagination {
        return true
      }
      return false
    }

    #expect(viewModel.state.items.map(\.id) == [1])
    #expect(viewModel.state.phase == .loaded)
  }

  @MainActor
  @Test("Pagination cancellation preserves current items")
  func viewModelPaginationCancellationPreservesItems() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      if page == 2 {
        throw AppError.cancelled
      }
      return RepositoryPage(
        items: [repositorySummary(id: 1)],
        currentPage: 1,
        hasNextPage: true,
        totalCount: 2
      )
    }
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }
    viewModel.loadNextPage()
    try await waitFor {
      repository.calls.contains { $0.page == 2 }
        && viewModel.state.pagination == .idle
    }

    #expect(viewModel.state.items.map(\.id) == [1])
    #expect(viewModel.state.phase == .loaded)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Stale pagination success preserves replacement request ownership")
  func viewModelStalePaginationSuccessPreservesReplacementOwnership() async throws {
    let repository = ControlledPaginationRepository(
      initialPages: [
        "swift": RepositoryPage(
          items: [repositorySummary(id: 1)],
          currentPage: 1,
          hasNextPage: true,
          totalCount: 2
        ),
        "swiftui": RepositoryPage(
          items: [repositorySummary(id: 10)],
          currentPage: 1,
          hasNextPage: true,
          totalCount: 2
        ),
      ]
    )
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.items.map(\.id) == [1] }
    viewModel.loadNextPage()
    await repository.waitUntilPageTwoStarts(query: "swift")

    viewModel.updateQuery("swiftui")
    try await waitFor { viewModel.state.items.map(\.id) == [10] }
    viewModel.loadNextPage()
    await repository.waitUntilPageTwoStarts(query: "swiftui")
    viewModel.loadNextPage()

    #expect(await repository.pageTwoCallCount(query: "swiftui") == 1)
    #expect(
      await repository.completePageTwo(
        query: "swift",
        result: .success(
          RepositoryPage(
            items: [repositorySummary(id: 2)],
            currentPage: 2,
            hasNextPage: false,
            totalCount: 2
          )
        )
      )
    )
    await repository.waitUntilPageTwoFinishes(query: "swift")
    await waitForMainActorTurn()

    #expect(viewModel.state.query == "swiftui")
    #expect(viewModel.state.items.map(\.id) == [10])
    #expect(viewModel.state.phase == .loaded)
    #expect(viewModel.state.pagination == .loadingNextPage)
    viewModel.loadNextPage()
    #expect(await repository.pageTwoCallCount(query: "swiftui") == 1)

    #expect(
      await repository.completeAllPageTwo(
        query: "swiftui",
        result: .success(
          RepositoryPage(
            items: [repositorySummary(id: 11)],
            currentPage: 2,
            hasNextPage: false,
            totalCount: 2
          )
        )
      ) == 1
    )
    try await waitFor { viewModel.state.items.map(\.id) == [10, 11] }

    #expect(viewModel.state.query == "swiftui")
    #expect(viewModel.state.pagination == .endReached)
    #expect(await repository.pageTwoCallCount(query: "swiftui") == 1)
  }

  @MainActor
  @Test("Stale pagination cancellation preserves replacement request ownership")
  func viewModelStalePaginationCancellationPreservesReplacementOwnership() async throws {
    let repository = ControlledPaginationRepository(
      initialPages: [
        "swift": RepositoryPage(
          items: [repositorySummary(id: 1)],
          currentPage: 1,
          hasNextPage: true,
          totalCount: 2
        ),
        "swiftui": RepositoryPage(
          items: [repositorySummary(id: 10)],
          currentPage: 1,
          hasNextPage: true,
          totalCount: 2
        ),
      ]
    )
    let viewModel = SearchViewModel(
      repository: repository,
      favoritesStore: makeFavoritesStore(),
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.items.map(\.id) == [1] }
    viewModel.loadNextPage()
    await repository.waitUntilPageTwoStarts(query: "swift")

    viewModel.updateQuery("swiftui")
    try await waitFor { viewModel.state.items.map(\.id) == [10] }
    viewModel.loadNextPage()
    await repository.waitUntilPageTwoStarts(query: "swiftui")
    viewModel.loadNextPage()

    #expect(await repository.pageTwoCallCount(query: "swiftui") == 1)
    #expect(
      await repository.completePageTwo(
        query: "swift",
        result: .cancellation
      )
    )
    await repository.waitUntilPageTwoFinishes(query: "swift")
    await waitForMainActorTurn()

    #expect(viewModel.state.query == "swiftui")
    #expect(viewModel.state.items.map(\.id) == [10])
    #expect(viewModel.state.phase == .loaded)
    #expect(viewModel.state.pagination == .loadingNextPage)
    #expect(viewModel.state.error == nil)
    viewModel.loadNextPage()
    #expect(await repository.pageTwoCallCount(query: "swiftui") == 1)

    #expect(
      await repository.completeAllPageTwo(
        query: "swiftui",
        result: .success(
          RepositoryPage(
            items: [repositorySummary(id: 11)],
            currentPage: 2,
            hasNextPage: false,
            totalCount: 2
          )
        )
      ) == 1
    )
    try await waitFor { viewModel.state.items.map(\.id) == [10, 11] }

    #expect(viewModel.state.query == "swiftui")
    #expect(viewModel.state.pagination == .endReached)
    #expect(await repository.pageTwoCallCount(query: "swiftui") == 1)
  }
}

struct HTTPResponse: Sendable {
  let statusCode: Int
  let headers: [String: String]
  let data: Data
}

final class MockURLProtocolStore: @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest) throws -> HTTPResponse

  private let handler: Handler

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func response(for request: URLRequest) throws -> HTTPResponse {
    try handler(request)
  }
}

func makeSession(store: MockURLProtocolStore) -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [MockURLProtocol.self]
  configuration.timeoutIntervalForRequest = 5
  configuration.timeoutIntervalForResource = 5
  configuration.urlCache = nil
  configuration.httpAdditionalHeaders = [MockURLProtocol.storeHeader: storeIdentifier(for: store)]
  MockURLProtocol.register(store)
  return URLSession(configuration: configuration)
}

private func makeAPIClient(response: HTTPResponse) -> GitHubAPIClient {
  guard let baseURL = URL(string: "https://api.github.test") else {
    preconditionFailure("Invalid test API base URL")
  }

  let store = MockURLProtocolStore { _ in response }
  return GitHubAPIClient(
    baseURL: baseURL,
    session: makeSession(store: store)
  )
}

private func storeIdentifier(for store: MockURLProtocolStore) -> String {
  String(ObjectIdentifier(store).hashValue)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  static let storeHeader = "X-Mock-Store-ID"
  private static let lock = NSLock()
  private nonisolated(unsafe) static var stores: [String: MockURLProtocolStore] = [:]

  static func register(_ store: MockURLProtocolStore) {
    lock.withLock {
      stores[storeIdentifier(for: store)] = store
    }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.value(forHTTPHeaderField: storeHeader) != nil
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let storeID = request.value(forHTTPHeaderField: Self.storeHeader) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    let store = Self.lock.withLock { Self.stores[storeID] }

    guard let store else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let result = try store.response(for: request)
      guard
        let requestURL = request.url,
        let response = HTTPURLResponse(
          url: requestURL,
          statusCode: result.statusCode,
          httpVersion: nil,
          headerFields: result.headers
        )
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: result.data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.withLock { storage }
  }

  func increment() {
    lock.withLock {
      storage += 1
    }
  }
}

private final class MockRepositoriesRepository: RepositoriesRepository, @unchecked Sendable {
  typealias Handler = @Sendable (_ query: String, _ page: Int, _ callCount: Int) async throws -> RepositoryPage

  private let lock = NSLock()
  private let handler: Handler
  private var storage: [(query: String, page: Int)] = []

  var calls: [(query: String, page: Int)] {
    lock.withLock { storage }
  }

  var callCount: Int {
    lock.withLock { storage.count }
  }

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func searchRepositories(query: String, page: Int, perPage: Int) async throws -> RepositoryPage {
    let count = lock.withLock {
      storage.append((query, page))
      return storage.count
    }
    return try await handler(query, page, count)
  }

  func repositoryDetails(owner: String, name: String) async throws -> RepositoryDetails {
    throw AppError.unknown
  }

  func repository(id: Int) async throws -> RepositorySummary {
    throw AppError.unknown
  }

  func repositoryReadme(owner: String, name: String) async throws -> RepositoryReadme {
    throw AppError.unknown
  }
}

private enum ControlledPaginationResult: Sendable {
  case success(RepositoryPage)
  case cancellation
}

private actor ControlledPaginationRepository: RepositoriesRepository {
  private let initialPages: [String: RepositoryPage]
  private var pageTwoCalls: [String: Int] = [:]
  private var pageTwoContinuations: [
    String: [CheckedContinuation<RepositoryPage, any Error>]
  ] = [:]
  private var pageTwoStartWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
  private var finishedPageTwoQueries: Set<String> = []
  private var pageTwoFinishWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

  init(initialPages: [String: RepositoryPage]) {
    self.initialPages = initialPages
  }

  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage {
    if page == 1, let initialPage = initialPages[query] {
      return initialPage
    }

    guard page == 2 else {
      throw AppError.notFound
    }

    pageTwoCalls[query, default: 0] += 1
    let startWaiters = pageTwoStartWaiters.removeValue(forKey: query) ?? []
    startWaiters.forEach { $0.resume() }

    do {
      let page = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<RepositoryPage, any Error>) in
        pageTwoContinuations[query, default: []].append(continuation)
      }
      markPageTwoFinished(query: query)
      return page
    } catch {
      markPageTwoFinished(query: query)
      throw error
    }
  }

  func waitUntilPageTwoStarts(query: String) async {
    guard pageTwoCalls[query, default: 0] == 0 else {
      return
    }

    await withCheckedContinuation { continuation in
      pageTwoStartWaiters[query, default: []].append(continuation)
    }
  }

  func waitUntilPageTwoFinishes(query: String) async {
    guard !finishedPageTwoQueries.contains(query) else {
      return
    }

    await withCheckedContinuation { continuation in
      pageTwoFinishWaiters[query, default: []].append(continuation)
    }
  }

  func completePageTwo(
    query: String,
    result: ControlledPaginationResult
  ) -> Bool {
    guard
      var continuations = pageTwoContinuations[query],
      !continuations.isEmpty
    else {
      return false
    }

    let continuation = continuations.removeFirst()
    pageTwoContinuations[query] = continuations
    resume(continuation, with: result)
    return true
  }

  func completeAllPageTwo(
    query: String,
    result: ControlledPaginationResult
  ) -> Int {
    let continuations = pageTwoContinuations.removeValue(forKey: query) ?? []
    continuations.forEach { continuation in
      resume(continuation, with: result)
    }
    return continuations.count
  }

  func pageTwoCallCount(query: String) -> Int {
    pageTwoCalls[query, default: 0]
  }

  private func markPageTwoFinished(query: String) {
    finishedPageTwoQueries.insert(query)
    let finishWaiters = pageTwoFinishWaiters.removeValue(forKey: query) ?? []
    finishWaiters.forEach { $0.resume() }
  }

  private func resume(
    _ continuation: CheckedContinuation<RepositoryPage, any Error>,
    with result: ControlledPaginationResult
  ) {
    switch result {
    case .success(let page):
      continuation.resume(returning: page)
    case .cancellation:
      continuation.resume(throwing: CancellationError())
    }
  }

  func repositoryDetails(owner: String, name: String) async throws -> RepositoryDetails {
    throw AppError.unknown
  }

  func repository(id: Int) async throws -> RepositorySummary {
    throw AppError.unknown
  }

  func repositoryReadme(owner: String, name: String) async throws -> RepositoryReadme {
    throw AppError.unknown
  }
}

private struct CancellingAccessTokenProvider: AccessTokenProvider {
  func accessToken() async throws -> String? {
    throw CancellationError()
  }
}

private func repositorySummary(id: Int, fullName: String? = nil) -> RepositorySummary {
  RepositorySummary(
    id: id,
    name: "repo-\(id)",
    fullName: fullName ?? "owner/repo-\(id)",
    owner: RepositoryOwner(id: 10, login: "owner", avatarURL: nil, profileURL: nil),
    description: "Description",
    starsCount: 100,
    forksCount: 5,
    language: "Swift",
    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
    repositoryURL: URL(string: "https://github.com/owner/repo-\(id)")
  )
}

private func sampleSearchResponseData(
  totalCount: Int,
  id: Int,
  fullName: String,
  isIncomplete: Bool = false
) -> Data {
  Data(
    """
    {
      "total_count": \(totalCount),
      "incomplete_results": \(isIncomplete),
      "items": [
        {
          "id": \(id),
          "name": "swift",
          "full_name": "\(fullName)",
          "owner": {
            "id": 10,
            "login": "apple",
            "avatar_url": "https://avatars.githubusercontent.com/u/10639145?v=4",
            "html_url": "https://github.com/apple"
          },
          "description": "The Swift Programming Language",
          "stargazers_count": 100,
          "forks_count": 5,
          "language": "Swift",
          "updated_at": "2026-07-24T10:15:30Z",
          "html_url": "https://github.com/apple/swift"
        }
      ]
    }
    """.utf8
  )
}

private func sampleRepositoryData(id: Int, fullName: String) -> Data {
  let name = fullName.split(separator: "/").last.map(String.init) ?? "repository"
  return Data(
    """
    {
      "id": \(id),
      "name": "\(name)",
      "full_name": "\(fullName)",
      "owner": {
        "id": 10,
        "login": "apple",
        "avatar_url": null,
        "html_url": "https://github.com/apple",
        "type": "Organization"
      },
      "description": "Description",
      "stargazers_count": 100,
      "forks_count": 5,
      "language": "Swift",
      "updated_at": "2024-01-01T00:00:00Z",
      "html_url": "https://github.com/\(fullName)"
    }
    """.utf8
  )
}

@MainActor
private func waitFor(
  timeout: Duration = .seconds(1),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let start = ContinuousClock.now
  while !condition() {
    if ContinuousClock.now - start > timeout {
      Issue.record("Timed out waiting for condition")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

@MainActor
private func waitForMainActorTurn() async {
  await withCheckedContinuation { continuation in
    Task { @MainActor in
      continuation.resume()
    }
  }
}
