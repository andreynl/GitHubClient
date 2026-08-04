#if DEBUG
import Foundation

nonisolated enum PreviewResponse<Value: Sendable>: Sendable {
  case success(Value)
  case failure(AppError)
  case pending

  func value() async throws -> Value {
    switch self {
    case .success(let value):
      return value
    case .failure(let error):
      throw error
    case .pending:
      try await Task.sleep(for: .seconds(3_600))
      throw CancellationError()
    }
  }
}

nonisolated struct PreviewRepositoriesRepository: RepositoriesRepository {
  let search: PreviewResponse<RepositoryPage>
  let details: PreviewResponse<RepositoryDetails>
  let summaryByID: [Int: PreviewResponse<RepositorySummary>]
  let readme: PreviewResponse<RepositoryReadme>

  init(
    search: PreviewResponse<RepositoryPage> = .success(
      RepositoryPage(
        items: [PreviewData.summary],
        currentPage: 1,
        hasNextPage: false,
        totalCount: 1
      )
    ),
    details: PreviewResponse<RepositoryDetails> = .success(PreviewData.details),
    summaryByID: [Int: PreviewResponse<RepositorySummary>] = [
      PreviewData.summary.id: .success(PreviewData.summary)
    ],
    readme: PreviewResponse<RepositoryReadme> = .success(
      RepositoryReadme(content: "# GitHubClient\n\nDeterministic preview content.")
    )
  ) {
    self.search = search
    self.details = details
    self.summaryByID = summaryByID
    self.readme = readme
  }

  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage {
    try await search.value()
  }

  func repositoryDetails(owner: String, name: String) async throws -> RepositoryDetails {
    try await details.value()
  }

  func repository(id: Int) async throws -> RepositorySummary {
    try await (summaryByID[id] ?? .failure(.notFound)).value()
  }

  func repositoryReadme(owner: String, name: String) async throws -> RepositoryReadme {
    try await readme.value()
  }
}

actor PreviewFavoritesRepository: FavoritesRepository {
  private var ids: Set<Int>

  init(ids: Set<Int>) {
    self.ids = ids
  }

  func favoriteRepositoryIDs() async throws -> Set<Int> {
    ids
  }

  func setFavorite(_ isFavorite: Bool, repositoryID: Int) async throws {
    if isFavorite {
      ids.insert(repositoryID)
    } else {
      ids.remove(repositoryID)
    }
  }
}

actor PreviewSearchHistoryRepository: SearchHistoryRepository {
  private var entries: [SearchHistoryEntry]
  private let loadResponse: PreviewResponse<[SearchHistoryEntry]>
  private let clearResponse: PreviewResponse<Void>

  init(
    entries: [SearchHistoryEntry] = [],
    loadResponse: PreviewResponse<[SearchHistoryEntry]>? = nil,
    clearResponse: PreviewResponse<Void> = .success(())
  ) {
    self.entries = entries
    self.loadResponse = loadResponse ?? .success(entries)
    self.clearResponse = clearResponse
  }

  func loadHistory() async throws -> [SearchHistoryEntry] {
    try await loadResponse.value()
  }

  func recordSuccessfulQuery(_ query: String) async throws
    -> [SearchHistoryEntry] {
    entries.removeAll {
      $0.query.caseInsensitiveCompare(query) == .orderedSame
    }
    entries.insert(SearchHistoryEntry(query: query), at: 0)
    return entries
  }

  func clearHistory() async throws {
    try await clearResponse.value()
    entries = []
  }
}

nonisolated enum PreviewData {
  static let owner = RepositoryOwner(
    id: 1,
    login: "apple",
    avatarURL: URL(string: "https://avatars.githubusercontent.com/u/10639145"),
    profileURL: URL(string: "https://github.com/apple")
  )

  static let summary = RepositorySummary(
    id: 1,
    name: "swift",
    fullName: "apple/swift",
    owner: owner,
    description: "The Swift Programming Language",
    starsCount: 68_000,
    forksCount: 10_000,
    language: "Swift",
    updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
    repositoryURL: URL(string: "https://github.com/apple/swift")
  )

  static let details = RepositoryDetails(
    id: summary.id,
    name: summary.name,
    fullName: summary.fullName,
    owner: owner,
    description: summary.description,
    starsCount: summary.starsCount,
    forksCount: summary.forksCount,
    subscribersCount: 2_100,
    openIssuesCount: 7_000,
    language: summary.language,
    defaultBranch: "main",
    licenseName: "Apache License 2.0",
    topics: ["compiler", "language", "swift"],
    createdAt: Date(timeIntervalSince1970: 1_400_000_000),
    updatedAt: summary.updatedAt,
    pushedAt: summary.updatedAt,
    repositoryURL: summary.repositoryURL,
    homepageURL: URL(string: "https://swift.org"),
    isArchived: false,
    isFork: false
  )
}

@MainActor
enum PreviewFactory {
  static func favoritesStore(ids: Set<Int> = []) -> FavoritesStore {
    FavoritesStore(repository: PreviewFavoritesRepository(ids: ids))
  }

  static func container() -> AppContainer {
    let repository = PreviewRepositoriesRepository()
    return AppContainer(
      repositoriesRepository: repository,
      favoritesStore: favoritesStore(ids: [PreviewData.summary.id]),
      searchHistoryRepository: PreviewSearchHistoryRepository()
    )
  }

  static func searchViewModel(
    response: PreviewResponse<RepositoryPage>
  ) -> SearchViewModel {
    let viewModel = SearchViewModel(
      repository: PreviewRepositoriesRepository(search: response),
      favoritesStore: favoritesStore(),
      historyRepository: PreviewSearchHistoryRepository(),
      debounceDuration: .zero
    )
    viewModel.updateQuery("swift")
    return viewModel
  }

  static func detailsViewModel(
    response: PreviewResponse<RepositoryDetails>,
    favorite: Bool
  ) -> RepositoryDetailsViewModel {
    RepositoryDetailsViewModel(
      owner: PreviewData.owner.login,
      name: PreviewData.details.name,
      repository: PreviewRepositoriesRepository(details: response),
      favoritesStore: favoritesStore(ids: favorite ? [PreviewData.details.id] : [])
    )
  }

  static func favoritesViewModel() -> FavoritesViewModel {
    let unavailable = RepositorySummary(
      id: 2,
      name: "unavailable",
      fullName: "owner/unavailable",
      owner: PreviewData.owner,
      description: nil,
      starsCount: 0,
      forksCount: 0,
      language: nil,
      updatedAt: nil,
      repositoryURL: nil
    )
    let repository = PreviewRepositoriesRepository(
      summaryByID: [
        PreviewData.summary.id: .success(PreviewData.summary),
        unavailable.id: .failure(.offline),
      ]
    )
    return FavoritesViewModel(
      repository: repository,
      favoritesStore: favoritesStore(ids: [PreviewData.summary.id, unavailable.id])
    )
  }
}
#endif
