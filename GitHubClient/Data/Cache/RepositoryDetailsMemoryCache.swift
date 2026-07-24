import Foundation

nonisolated struct RepositoryDetailsCacheKey: Hashable, Sendable {
  let owner: String
  let name: String

  init(owner: String, name: String) {
    self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

/// Process-local cache. Explicit refresh and expiry belong to a later caching phase.
actor RepositoryDetailsMemoryCache {
  private var detailsByKey: [RepositoryDetailsCacheKey: RepositoryDetails] = [:]

  func value(for key: RepositoryDetailsCacheKey) -> RepositoryDetails? {
    detailsByKey[key]
  }

  func store(_ details: RepositoryDetails, for key: RepositoryDetailsCacheKey) {
    detailsByKey[key] = details
  }

  func removeAll() {
    detailsByKey.removeAll()
  }
}
