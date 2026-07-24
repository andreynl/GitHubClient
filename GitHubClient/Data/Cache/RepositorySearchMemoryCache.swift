nonisolated struct RepositorySearchCacheKey: Hashable, Sendable {
  let query: String
  let page: Int
  let perPage: Int
}

actor RepositorySearchMemoryCache {
  private var pages: [RepositorySearchCacheKey: RepositoryPage] = [:]

  func value(for key: RepositorySearchCacheKey) -> RepositoryPage? {
    guard let page = pages[key] else {
      return nil
    }

    return RepositoryPage(
      items: page.items,
      currentPage: page.currentPage,
      hasNextPage: page.hasNextPage,
      totalCount: page.totalCount,
      isFromCache: true
    )
  }

  func store(_ page: RepositoryPage, for key: RepositorySearchCacheKey) {
    pages[key] = RepositoryPage(
      items: page.items,
      currentPage: page.currentPage,
      hasNextPage: page.hasNextPage,
      totalCount: page.totalCount,
      isFromCache: false
    )
  }

  func removeAll() {
    pages.removeAll()
  }
}
