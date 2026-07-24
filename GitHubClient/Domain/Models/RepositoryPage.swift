nonisolated struct RepositoryPage: Equatable, Sendable {
  let items: [RepositorySummary]
  let currentPage: Int
  let hasNextPage: Bool
  let totalCount: Int?
  let isFromCache: Bool

  init(
    items: [RepositorySummary],
    currentPage: Int,
    hasNextPage: Bool,
    totalCount: Int?,
    isFromCache: Bool = false
  ) {
    self.items = items
    self.currentPage = currentPage
    self.hasNextPage = hasNextPage
    self.totalCount = totalCount
    self.isFromCache = isFromCache
  }
}
