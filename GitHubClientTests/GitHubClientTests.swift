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

    let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
    let queryItems = try #require(components?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "q", value: "swift ui")))
    #expect(queryItems.contains(URLQueryItem(name: "page", value: "2")))
    #expect(queryItems.contains(URLQueryItem(name: "per_page", value: "25")))
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
    #expect(!first.isFromCache)
    #expect(second.isFromCache)
  }

  @MainActor
  @Test("Search view model loads successful results")
  func viewModelSuccess() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      RepositoryPage(items: [repositorySummary(id: page)], currentPage: page, hasNextPage: false, totalCount: 1)
    }
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

    viewModel.updateQuery("swift")
    try await waitFor { viewModel.state.phase == .loaded }

    #expect(viewModel.state.items.count == 1)
    #expect(viewModel.state.pagination == .endReached)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Search view model handles empty results")
  func viewModelEmpty() async throws {
    let repository = MockRepositoriesRepository { _, page, _ in
      RepositoryPage(items: [], currentPage: page, hasNextPage: false, totalCount: 0)
    }
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

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
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

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
      minimumQueryLength: 3,
      debounceDuration: .milliseconds(1)
    )

    viewModel.updateQuery("sw")
    try await Task.sleep(for: .milliseconds(40))

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
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(50))

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
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

    viewModel.updateQuery("swift")
    try await Task.sleep(for: .milliseconds(10))
    viewModel.updateQuery("swiftui")
    try await waitFor { viewModel.state.items.map(\.id) == [2] }
    try await Task.sleep(for: .milliseconds(120))

    #expect(viewModel.state.items.map(\.id) == [2])
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
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

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
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

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
    let viewModel = SearchViewModel(repository: repository, debounceDuration: .milliseconds(1))

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
}

private struct HTTPResponse: Sendable {
  let statusCode: Int
  let headers: [String: String]
  let data: Data
}

private final class MockURLProtocolStore: @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest) throws -> HTTPResponse

  private let handler: Handler

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func response(for request: URLRequest) throws -> HTTPResponse {
    try handler(request)
  }
}

private func makeSession(store: MockURLProtocolStore) -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [MockURLProtocol.self]
  configuration.timeoutIntervalForRequest = 5
  configuration.timeoutIntervalForResource = 5
  configuration.urlCache = nil
  configuration.httpAdditionalHeaders = [MockURLProtocol.storeHeader: storeIdentifier(for: store)]
  MockURLProtocol.register(store)
  return URLSession(configuration: configuration)
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

private final class LockedCounter: @unchecked Sendable {
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

private func sampleSearchResponseData(totalCount: Int, id: Int, fullName: String) -> Data {
  Data(
    """
    {
      "total_count": \(totalCount),
      "incomplete_results": false,
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
