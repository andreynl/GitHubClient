import Foundation

nonisolated struct RepositorySearchCacheKey: Hashable, Sendable {
  let query: String
  let page: Int
  let perPage: Int
}

actor RepositorySearchMemoryCache {
  private struct Entry {
    let page: RepositoryPage
    let storedAt: TimeInterval
    var accessOrder: UInt64
  }

  private let policy: MemoryCachePolicy
  private let clock: CacheClock
  private var entries: [RepositorySearchCacheKey: Entry] = [:]
  private var accessOrder: UInt64 = 0

  init(
    policy: MemoryCachePolicy = .search,
    clock: CacheClock = SystemCacheClock()
  ) {
    self.policy = policy
    self.clock = clock
  }

  func value(for key: RepositorySearchCacheKey) -> RepositoryPage? {
    guard var entry = entries[key] else {
      return nil
    }

    guard clock.now() - entry.storedAt < policy.timeToLive else {
      entries[key] = nil
      return nil
    }

    entry.accessOrder = nextAccessOrder()
    entries[key] = entry

    return entry.page
  }

  func store(_ page: RepositoryPage, for key: RepositorySearchCacheKey) {
    entries[key] = Entry(
      page: page,
      storedAt: clock.now(),
      accessOrder: nextAccessOrder()
    )
    evictIfNeeded()
  }

  private func nextAccessOrder() -> UInt64 {
    accessOrder &+= 1
    return accessOrder
  }

  private func evictIfNeeded() {
    while entries.count > policy.maximumEntryCount {
      guard let key = entries.min(by: {
        $0.value.accessOrder < $1.value.accessOrder
      })?.key else {
        return
      }
      entries[key] = nil
    }
  }
}
