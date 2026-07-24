import Foundation
import Testing

@testable import GitHubClient

@Suite("Phase 2.1 repository details")
struct RepositoryDetailsTests {
  @Test("Details endpoint constructs repository path without manual encoding")
  func endpointConstruction() throws {
    let endpoint = GitHubEndpoint.repositoryDetails(owner: "apple org", name: "swift package")
    let baseURL = try #require(URL(string: "https://api.github.com"))
    let request = try endpoint.urlRequest(baseURL: baseURL, accessToken: nil)

    #expect(request.url?.path == "/repos/apple org/swift package")
    #expect(request.url?.absoluteString.contains("apple%20org/swift%20package") == true)
    #expect(request.url?.query == nil)
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "GitHubClient")
  }

  @Test("Details DTO decodes and maps subscribers count")
  func decodingAndMapping() throws {
    let dto = try detailsDTO(from: repositoryDetailsData(id: 1, fullName: "apple/swift"))
    let details = dto.toDomain()

    #expect(details.id == 1)
    #expect(details.fullName == "apple/swift")
    #expect(details.owner.login == "apple")
    #expect(details.starsCount == 100)
    #expect(details.forksCount == 5)
    #expect(details.subscribersCount == 12)
    #expect(details.openIssuesCount == 7)
    #expect(details.defaultBranch == "main")
    #expect(details.licenseName == "Apache License 2.0")
    #expect(details.topics == ["compiler", "swift"])
    #expect(details.language == "Swift")
    #expect(details.createdAt != nil)
    #expect(details.updatedAt != nil)
    #expect(details.pushedAt != nil)
    #expect(details.repositoryURL == URL(string: "https://github.com/apple/swift"))
    #expect(details.homepageURL == URL(string: "https://swift.org"))
    #expect(details.isArchived == false)
    #expect(details.isFork == false)
  }

  @Test("Details DTO accepts nullable license homepage and dates")
  func nullableDetailsFields() throws {
    let dto = try detailsDTO(
      from: repositoryDetailsData(
        id: 1,
        fullName: "apple/swift",
        optionalFieldsAreNull: true
      )
    )
    let details = dto.toDomain()

    #expect(details.licenseName == nil)
    #expect(details.homepageURL == nil)
    #expect(details.createdAt == nil)
    #expect(details.updatedAt == nil)
    #expect(details.pushedAt == nil)
  }

  @Test("Repository caches normalized owner and name for current process")
  func repositoryCaching() async throws {
    let counter = LockedCounter()
    let store = MockURLProtocolStore { request in
      counter.increment()
      #expect(request.url?.path == "/repos/Apple/Swift")
      return HTTPResponse(
        statusCode: 200,
        headers: [:],
        data: repositoryDetailsData(id: 1, fullName: "apple/swift")
      )
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    let first = try await repository.repositoryDetails(owner: "Apple", name: "Swift")
    let second = try await repository.repositoryDetails(owner: " apple ", name: " swift ")

    #expect(first == second)
    #expect(counter.value == 1)
  }

  @Test("Repository does not cache details failures")
  func repositoryDoesNotCacheFailures() async throws {
    let counter = LockedCounter()
    let store = MockURLProtocolStore { _ in
      counter.increment()
      if counter.value == 1 {
        return HTTPResponse(statusCode: 500, headers: [:], data: Data())
      }
      return HTTPResponse(
        statusCode: 200,
        headers: [:],
        data: repositoryDetailsData(id: 1, fullName: "apple/swift")
      )
    }
    let repository = GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient(
        baseURL: try #require(URL(string: "https://api.github.test")),
        session: makeSession(store: store)
      )
    )

    await #expect(throws: AppError.server(statusCode: 500)) {
      _ = try await repository.repositoryDetails(owner: "apple", name: "swift")
    }
    let details = try await repository.repositoryDetails(owner: "apple", name: "swift")

    #expect(details.id == 1)
    #expect(counter.value == 2)
  }

  @MainActor
  @Test("Details view model loads successfully")
  func viewModelSuccess() async throws {
    let repository = DetailsRepositoriesRepositoryStub { _, _, _ in
      repositoryDetails(id: 1)
    }
    let viewModel = RepositoryDetailsViewModel(owner: "apple", name: "swift", repository: repository)

    #expect(viewModel.state == .idle)
    viewModel.load()
    try await waitForDetails { viewModel.state.phase == .loaded }

    #expect(viewModel.state.details?.id == 1)
    #expect(viewModel.state.error == nil)
  }

  @MainActor
  @Test("Details view model exposes errors and retries")
  func viewModelFailureAndRetry() async throws {
    let repository = DetailsRepositoriesRepositoryStub { _, _, callCount in
      if callCount == 1 {
        throw AppError.offline
      }
      return repositoryDetails(id: 2)
    }
    let viewModel = RepositoryDetailsViewModel(owner: "apple", name: "swift", repository: repository)

    viewModel.load()
    try await waitForDetails { viewModel.state.phase == .failed }
    #expect(viewModel.state.error == .offline)

    viewModel.retry()
    try await waitForDetails { viewModel.state.phase == .loaded }
    #expect(viewModel.state.details?.id == 2)
    #expect(repository.callCount == 2)
  }

  @MainActor
  @Test("Details view model prevents duplicate loads")
  func viewModelDuplicateLoadPrevention() async throws {
    let repository = DetailsRepositoriesRepositoryStub { _, _, _ in
      try await Task.sleep(for: .milliseconds(50))
      return repositoryDetails(id: 1)
    }
    let viewModel = RepositoryDetailsViewModel(owner: "apple", name: "swift", repository: repository)

    viewModel.load()
    viewModel.load()
    try await waitForDetails { viewModel.state.phase == .loaded }

    #expect(repository.callCount == 1)
  }

  @MainActor
  @Test("Details view model cancellation prevents stale responses")
  func viewModelCancellationAndStaleResponsePrevention() async throws {
    let repository = DetailsRepositoriesRepositoryStub { _, _, callCount in
      if callCount == 1 {
        do {
          try await Task.sleep(for: .milliseconds(80))
        } catch is CancellationError {
          // Return stale data deliberately to verify request identity protection.
        }
        return repositoryDetails(id: 1)
      }
      return repositoryDetails(id: 2)
    }
    let viewModel = RepositoryDetailsViewModel(owner: "apple", name: "swift", repository: repository)

    viewModel.load()
    try await waitForDetails { repository.callCount == 1 }
    viewModel.cancel()
    #expect(viewModel.state.phase == .idle)
    #expect(viewModel.state.error == nil)

    viewModel.load()
    try await waitForDetails { viewModel.state.details?.id == 2 }
    try await Task.sleep(for: .milliseconds(100))

    #expect(viewModel.state.details?.id == 2)
    #expect(viewModel.state.error == nil)
  }
}

private final class DetailsRepositoriesRepositoryStub: RepositoriesRepository, @unchecked Sendable {
  typealias Handler =
    @Sendable (_ owner: String, _ name: String, _ callCount: Int) async throws
    -> RepositoryDetails

  private let lock = NSLock()
  private let handler: Handler
  private var detailsCallCount = 0

  var callCount: Int {
    lock.withLock { detailsCallCount }
  }

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func searchRepositories(query: String, page: Int, perPage: Int) async throws -> RepositoryPage {
    throw AppError.unknown("Repository search is not configured for this details test.")
  }

  func repositoryDetails(owner: String, name: String) async throws -> RepositoryDetails {
    let count = lock.withLock {
      detailsCallCount += 1
      return detailsCallCount
    }
    return try await handler(owner, name, count)
  }
}

private func detailsDTO(from data: Data) throws -> RepositoryDetailsDTO {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  return try decoder.decode(RepositoryDetailsDTO.self, from: data)
}

private func repositoryDetails(id: Int) -> RepositoryDetails {
  RepositoryDetails(
    id: id,
    name: "swift",
    fullName: "apple/swift",
    owner: RepositoryOwner(id: 10, login: "apple", avatarURL: nil, profileURL: nil),
    description: "The Swift Programming Language",
    starsCount: 100,
    forksCount: 5,
    subscribersCount: 12,
    openIssuesCount: 7,
    language: "Swift",
    defaultBranch: "main",
    licenseName: "Apache License 2.0",
    topics: ["compiler", "swift"],
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    updatedAt: Date(timeIntervalSince1970: 1_700_100_000),
    pushedAt: Date(timeIntervalSince1970: 1_700_200_000),
    repositoryURL: URL(string: "https://github.com/apple/swift"),
    homepageURL: URL(string: "https://swift.org"),
    isArchived: false,
    isFork: false
  )
}

private func repositoryDetailsData(
  id: Int,
  fullName: String,
  optionalFieldsAreNull: Bool = false
) -> Data {
  let optionalString = optionalFieldsAreNull ? "null" : "\"2026-07-24T10:15:30Z\""
  let license = optionalFieldsAreNull ? "null" : "{\"name\":\"Apache License 2.0\"}"
  let homepage = optionalFieldsAreNull ? "null" : "\"https://swift.org\""

  return Data(
    """
    {
      "id": \(id),
      "name": "swift",
      "full_name": "\(fullName)",
      "owner": {
        "id": 10,
        "login": "apple",
        "avatar_url": "https://avatars.githubusercontent.com/u/10",
        "html_url": "https://github.com/apple"
      },
      "description": "The Swift Programming Language",
      "stargazers_count": 100,
      "watchers_count": 999,
      "forks_count": 5,
      "subscribers_count": 12,
      "open_issues_count": 7,
      "language": "Swift",
      "default_branch": "main",
      "license": \(license),
      "topics": ["compiler", "swift"],
      "created_at": \(optionalString),
      "updated_at": \(optionalString),
      "pushed_at": \(optionalString),
      "html_url": "https://github.com/apple/swift",
      "homepage": \(homepage),
      "archived": false,
      "fork": false
    }
    """.utf8
  )
}

@MainActor
private func waitForDetails(
  timeout: Duration = .seconds(1),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let start = ContinuousClock.now
  while !condition() {
    if ContinuousClock.now - start > timeout {
      Issue.record("Timed out waiting for details condition")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}
