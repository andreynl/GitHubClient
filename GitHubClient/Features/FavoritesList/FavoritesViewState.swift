nonisolated enum FavoritesViewState: Equatable, Sendable {
  case initializing
  case idle
  case loading
  case empty
  case loaded(
    repositories: [RepositorySummary],
    failedCount: Int,
    isRefreshing: Bool
  )
  case failed(AppError)
}
