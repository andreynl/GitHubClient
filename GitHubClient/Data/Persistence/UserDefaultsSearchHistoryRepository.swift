import Foundation

nonisolated protocol SearchHistoryPersistence: Sendable {
  func data(forKey key: String) async throws -> Data?
  func set(_ data: Data, forKey key: String) async throws
  func removeObject(forKey key: String) async throws
}

nonisolated final class UserDefaultsSearchHistoryPersistence:
  SearchHistoryPersistence,
  @unchecked Sendable
{
  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func data(forKey key: String) async throws -> Data? {
    defaults.data(forKey: key)
  }

  func set(_ data: Data, forKey key: String) async throws {
    defaults.set(data, forKey: key)
  }

  func removeObject(forKey key: String) async throws {
    defaults.removeObject(forKey: key)
  }
}

actor UserDefaultsSearchHistoryRepository: SearchHistoryRepository {
  private let persistence: any SearchHistoryPersistence
  private let key: String
  private let maximumCapacity: Int
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    defaults: UserDefaults = .standard,
    key: String = "com.andreynl.GitHubClient.searchHistory",
    maximumCapacity: Int
  ) {
    self.init(
      persistence: UserDefaultsSearchHistoryPersistence(defaults: defaults),
      key: key,
      maximumCapacity: maximumCapacity
    )
  }

  init(
    persistence: any SearchHistoryPersistence,
    key: String = "com.andreynl.GitHubClient.searchHistory",
    maximumCapacity: Int
  ) {
    precondition(maximumCapacity > 0)
    self.persistence = persistence
    self.key = key
    self.maximumCapacity = maximumCapacity
  }

  func loadHistory() async throws -> [SearchHistoryEntry] {
    do {
      try Task.checkCancellation()
      return try await loadEntries()
    } catch {
      throw mapPersistenceError(error)
    }
  }

  func recordSuccessfulQuery(_ query: String) async throws
    -> [SearchHistoryEntry] {
    do {
      try Task.checkCancellation()
      var entries = try await loadEntries()
      let displayQuery = query.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      entries.removeAll {
        $0.query.caseInsensitiveCompare(displayQuery) == .orderedSame
      }
      entries.insert(SearchHistoryEntry(query: displayQuery), at: 0)
      if entries.count > maximumCapacity {
        entries.removeLast(entries.count - maximumCapacity)
      }
      let data = try encoder.encode(entries.map(\.query))
      try Task.checkCancellation()
      try await persistence.set(data, forKey: key)
      return entries
    } catch {
      throw mapPersistenceError(error)
    }
  }

  func clearHistory() async throws {
    do {
      try Task.checkCancellation()
      try await persistence.removeObject(forKey: key)
    } catch {
      throw mapPersistenceError(error)
    }
  }

  private func loadEntries() async throws -> [SearchHistoryEntry] {
    guard let data = try await persistence.data(forKey: key) else {
      return []
    }
    return try decoder.decode([String].self, from: data).map {
      SearchHistoryEntry(query: $0)
    }
  }

  private func mapPersistenceError(_ error: Error) -> Error {
    if error is CancellationError || error as? AppError == .cancelled {
      return CancellationError()
    }
    return AppError.persistence
  }
}
