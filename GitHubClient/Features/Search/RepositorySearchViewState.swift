enum RepositorySearchPhase: Equatable, Sendable {
  case idle
  case initialLoading
  case loaded
  case empty
  case failed
}

enum PaginationState: Equatable, Sendable {
  case idle
  case loadingNextPage
  case failed(AppError)
  case endReached
}

struct RepositorySearchViewState: Equatable, Sendable {
  var query: String = ""
  var items: [RepositorySummary] = []
  var phase: RepositorySearchPhase = .idle
  var pagination: PaginationState = .idle
  var error: AppError?
  var isShowingCachedData: Bool = false
}
