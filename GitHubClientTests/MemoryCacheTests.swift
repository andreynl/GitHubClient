import Foundation
import Testing

@testable import GitHubClient

@Suite("In-memory cache policy")
struct MemoryCacheTests {
  @Test("Search cache returns fresh entries and expires stale entries")
  func searchFreshness() async {
    let clock = TestCacheClock()
    let cache = RepositorySearchMemoryCache(
      policy: MemoryCachePolicy(timeToLive: 300, maximumEntryCount: 2),
      clock: clock
    )
    let key = RepositorySearchCacheKey(query: "swift", page: 1, perPage: 30)
    let page = RepositoryPage(
      items: [cacheRepositorySummary(id: 1)],
      currentPage: 1,
      hasNextPage: false,
      totalCount: 1,
      isIncomplete: true
    )

    await cache.store(page, for: key)
    #expect(await cache.value(for: key) == page)

    clock.advance(by: 300)
    #expect(await cache.value(for: key) == nil)
  }

  @Test("Search cache evicts the least recently used entry deterministically")
  func searchCapacity() async {
    let clock = TestCacheClock()
    let cache = RepositorySearchMemoryCache(
      policy: MemoryCachePolicy(timeToLive: 300, maximumEntryCount: 2),
      clock: clock
    )
    let first = RepositorySearchCacheKey(query: "one", page: 1, perPage: 30)
    let second = RepositorySearchCacheKey(query: "two", page: 1, perPage: 30)
    let third = RepositorySearchCacheKey(query: "three", page: 1, perPage: 30)

    await cache.store(cachePage(id: 1), for: first)
    await cache.store(cachePage(id: 2), for: second)
    _ = await cache.value(for: first)
    await cache.store(cachePage(id: 3), for: third)

    #expect(await cache.value(for: first) != nil)
    #expect(await cache.value(for: second) == nil)
    #expect(await cache.value(for: third) != nil)
  }

  @Test("Replacing a search entry updates its value and freshness")
  func searchReplacement() async {
    let clock = TestCacheClock()
    let cache = RepositorySearchMemoryCache(
      policy: MemoryCachePolicy(timeToLive: 300, maximumEntryCount: 2),
      clock: clock
    )
    let key = RepositorySearchCacheKey(query: "swift", page: 1, perPage: 30)

    await cache.store(cachePage(id: 1), for: key)
    clock.advance(by: 299)
    await cache.store(cachePage(id: 2), for: key)
    clock.advance(by: 299)

    #expect(await cache.value(for: key)?.items.map(\.id) == [2])

    clock.advance(by: 1)
    #expect(await cache.value(for: key) == nil)
  }

  @Test("Details cache applies freshness and bounded LRU eviction")
  func detailsPolicy() async {
    let clock = TestCacheClock()
    let cache = RepositoryDetailsMemoryCache(
      policy: MemoryCachePolicy(timeToLive: 60, maximumEntryCount: 2),
      clock: clock
    )
    let first = RepositoryDetailsCacheKey(owner: "owner", name: "one")
    let second = RepositoryDetailsCacheKey(owner: "owner", name: "two")
    let third = RepositoryDetailsCacheKey(owner: "owner", name: "three")

    await cache.store(cacheRepositoryDetails(id: 1), for: first)
    await cache.store(cacheRepositoryDetails(id: 2), for: second)
    _ = await cache.value(for: first)
    await cache.store(cacheRepositoryDetails(id: 3), for: third)

    #expect(await cache.value(for: first)?.id == 1)
    #expect(await cache.value(for: second) == nil)
    #expect(await cache.value(for: third)?.id == 3)

    clock.advance(by: 60)
    #expect(await cache.value(for: first) == nil)
    #expect(await cache.value(for: third) == nil)
  }

  @Test("Search and details caches retain independent default policies")
  func defaultPolicies() {
    #expect(MemoryCachePolicy.search.timeToLive == 300)
    #expect(MemoryCachePolicy.search.maximumEntryCount == 100)
    #expect(MemoryCachePolicy.details.timeToLive == 300)
    #expect(MemoryCachePolicy.details.maximumEntryCount == 50)
  }
}

private final class TestCacheClock: CacheClock, @unchecked Sendable {
  private let lock = NSLock()
  private var instant: TimeInterval = 0

  func now() -> TimeInterval {
    lock.withLock { instant }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock {
      instant += interval
    }
  }
}

private func cachePage(id: Int) -> RepositoryPage {
  RepositoryPage(
    items: [cacheRepositorySummary(id: id)],
    currentPage: 1,
    hasNextPage: false,
    totalCount: 1
  )
}

private func cacheRepositorySummary(id: Int) -> RepositorySummary {
  RepositorySummary(
    id: id,
    name: "repository-\(id)",
    fullName: "owner/repository-\(id)",
    owner: RepositoryOwner(id: 1, login: "owner", avatarURL: nil, profileURL: nil),
    description: nil,
    starsCount: 0,
    forksCount: 0,
    language: nil,
    updatedAt: nil,
    repositoryURL: nil
  )
}

private func cacheRepositoryDetails(id: Int) -> RepositoryDetails {
  RepositoryDetails(
    id: id,
    name: "repository-\(id)",
    fullName: "owner/repository-\(id)",
    owner: RepositoryOwner(id: 1, login: "owner", avatarURL: nil, profileURL: nil),
    description: nil,
    starsCount: 0,
    forksCount: 0,
    subscribersCount: 0,
    openIssuesCount: 0,
    language: nil,
    defaultBranch: "main",
    licenseName: nil,
    topics: [],
    createdAt: nil,
    updatedAt: nil,
    pushedAt: nil,
    repositoryURL: nil,
    homepageURL: nil,
    isArchived: false,
    isFork: false
  )
}
