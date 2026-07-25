import Foundation

nonisolated struct RepositoryDetailsCacheKey: Hashable, Sendable {
  let owner: String
  let name: String

  init(owner: String, name: String) {
    self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

/// Process-local cache with bounded, time-based freshness.
actor RepositoryDetailsMemoryCache {
  private struct Entry {
    let details: RepositoryDetails
    let storedAt: TimeInterval
    var accessOrder: UInt64
  }

  private let policy: MemoryCachePolicy
  private let clock: CacheClock
  private var entries: [RepositoryDetailsCacheKey: Entry] = [:]
  private var accessOrder: UInt64 = 0

  init(
    policy: MemoryCachePolicy = .details,
    clock: CacheClock = SystemCacheClock()
  ) {
    self.policy = policy
    self.clock = clock
  }

  func value(for key: RepositoryDetailsCacheKey) -> RepositoryDetails? {
    guard var entry = entries[key] else {
      return nil
    }

    guard clock.now() - entry.storedAt < policy.timeToLive else {
      entries[key] = nil
      return nil
    }

    entry.accessOrder = nextAccessOrder()
    entries[key] = entry
    return entry.details
  }

  func store(_ details: RepositoryDetails, for key: RepositoryDetailsCacheKey) {
    entries[key] = Entry(
      details: details,
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
