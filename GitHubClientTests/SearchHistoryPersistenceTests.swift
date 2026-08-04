import Foundation
import Testing

@testable import GitHubClient

@Suite("Search History persistence")
struct SearchHistoryPersistenceTests {
  @Test("Search history entry preserves its display query")
  func entryPreservesDisplayQuery() async {
    let entry = SearchHistoryEntry(query: "SwiftUI")
    let transfer: @Sendable (SearchHistoryEntry) -> SearchHistoryEntry = {
      $0
    }

    #expect(entry == SearchHistoryEntry(query: "SwiftUI"))
    #expect(transfer(entry).query == "SwiftUI")
  }

  @Test("Persistence error has stable user-facing copy")
  func persistenceErrorMessage() {
    #expect(
      AppError.persistence.message
        == "Saved data could not be loaded or updated. Try again."
    )
  }

  @Test("Missing storage and round trip preserve newest-first order")
  func missingStorageAndRoundTrip() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )

    #expect(try await repository.loadHistory() == [])
    #expect(
      try await repository.recordSuccessfulQuery("Swift")
        == [SearchHistoryEntry(query: "Swift")]
    )
    let newestFirst = [
      SearchHistoryEntry(query: "SwiftUI"),
      SearchHistoryEntry(query: "Swift"),
    ]
    #expect(
      try await repository.recordSuccessfulQuery("SwiftUI")
        == newestFirst
    )

    let reloaded = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )
    #expect(try await reloaded.loadHistory() == newestFirst)
  }

  @Test("Recording trims duplicates and preserves latest spelling")
  func trimsDuplicateAndPreservesLatestSpelling() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )

    _ = try await repository.recordSuccessfulQuery("Swift")
    #expect(
      try await repository.recordSuccessfulQuery(" swift ")
        == [SearchHistoryEntry(query: "swift")]
    )
    _ = try await repository.recordSuccessfulQuery("Kotlin")
    let newestFirst = [
      SearchHistoryEntry(query: "SWIFT"),
      SearchHistoryEntry(query: "Kotlin"),
    ]
    #expect(
      try await repository.recordSuccessfulQuery("SWIFT")
        == newestFirst
    )

    let reloaded = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )
    #expect(try await reloaded.loadHistory() == newestFirst)
  }

  @Test("Recording a duplicate moves it to the front")
  func movesDuplicateToFront() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )

    _ = try await repository.recordSuccessfulQuery("Kotlin")
    _ = try await repository.recordSuccessfulQuery("Swift")
    let newestFirst = [
      SearchHistoryEntry(query: "KOTLIN"),
      SearchHistoryEntry(query: "Swift"),
    ]
    #expect(
      try await repository.recordSuccessfulQuery("KOTLIN")
        == newestFirst
    )

    let reloaded = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )
    #expect(try await reloaded.loadHistory() == newestFirst)
  }

  @Test("Capacity removes the oldest entry")
  func removesOldestBeyondCapacity() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 3
    )

    for query in ["A", "B", "C"] {
      _ = try await repository.recordSuccessfulQuery(query)
    }
    let newestFirst = [
      SearchHistoryEntry(query: "D"),
      SearchHistoryEntry(query: "C"),
      SearchHistoryEntry(query: "B"),
    ]
    #expect(
      try await repository.recordSuccessfulQuery("D") == newestFirst
    )

    let reloaded = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 3
    )
    #expect(try await reloaded.loadHistory() == newestFirst)
  }

  @Test("Capacity of one retains only the newest entry")
  func capacityOfOneRetainsNewest() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 1
    )

    _ = try await repository.recordSuccessfulQuery("Swift")
    let newest = [SearchHistoryEntry(query: "SwiftUI")]
    #expect(
      try await repository.recordSuccessfulQuery("SwiftUI") == newest
    )

    let reloaded = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 1
    )
    #expect(try await reloaded.loadHistory() == newest)
  }

  @Test("Clear removes all persisted history")
  func clearRemovesHistory() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )

    _ = try await repository.recordSuccessfulQuery("Swift")
    try await repository.clearHistory()

    let reloaded = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )
    #expect(try await reloaded.loadHistory() == [])
    #expect(storage.defaults.data(forKey: storage.key) == nil)
  }

  @Test("Corrupt history fails explicitly and remains unchanged")
  func corruptJSONRemainsUnchanged() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let corrupt = Data("not-json".utf8)
    storage.defaults.set(corrupt, forKey: storage.key)
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )

    await #expect(throws: AppError.persistence) {
      _ = try await repository.loadHistory()
    }
    await #expect(throws: AppError.persistence) {
      _ = try await repository.recordSuccessfulQuery("Swift")
    }
    await #expect(throws: AppError.persistence) {
      _ = try await repository.recordSuccessfulQuery("Swift")
    }
    #expect(storage.defaults.data(forKey: storage.key) == corrupt)
  }

  @Test("Wrong persisted shape fails and remains unchanged")
  func wrongPersistedShapeRemainsUnchanged() async throws {
    let storage = try makeStorage()
    defer { storage.cleanup() }
    let wrongShape = try JSONEncoder().encode([1, 2, 3])
    storage.defaults.set(wrongShape, forKey: storage.key)
    let repository = UserDefaultsSearchHistoryRepository(
      defaults: storage.defaults,
      key: storage.key,
      maximumCapacity: 10
    )

    await #expect(throws: AppError.persistence) {
      _ = try await repository.loadHistory()
    }
    #expect(storage.defaults.data(forKey: storage.key) == wrongShape)
  }

  @Test("Concurrent record operations do not lose updates")
  func concurrentRecordOperationsDoNotLoseUpdates() async throws {
    let persistence = ReentrantReadSearchHistoryPersistence()
    let repository = UserDefaultsSearchHistoryRepository(
      persistence: persistence,
      key: "history",
      maximumCapacity: 10
    )

    async let swiftResult = repository.recordSuccessfulQuery("Swift")
    async let swiftUIResult = repository.recordSuccessfulQuery("SwiftUI")
    let (firstResult, secondResult) = try await (swiftResult, swiftUIResult)
    let finalResult = try await repository.loadHistory()

    #expect(Set(finalResult.map(\.query)) == ["Swift", "SwiftUI"])
    #expect([firstResult.count, secondResult.count].sorted() == [1, 2])
    #expect(finalResult == (firstResult.count == 2 ? firstResult : secondResult))

  }

  @Test("Record and clear remain atomically ordered")
  func recordAndClearRemainAtomicallyOrdered() async throws {
    let recordThenClearStorage = try makeStorage()
    defer { recordThenClearStorage.cleanup() }
    let recordThenClear = UserDefaultsSearchHistoryRepository(
      defaults: recordThenClearStorage.defaults,
      key: recordThenClearStorage.key,
      maximumCapacity: 10
    )

    _ = try await recordThenClear.recordSuccessfulQuery("Swift")
    try await recordThenClear.clearHistory()
    #expect(try await recordThenClear.loadHistory() == [])

    let clearThenRecordStorage = try makeStorage()
    defer { clearThenRecordStorage.cleanup() }
    let clearThenRecord = UserDefaultsSearchHistoryRepository(
      defaults: clearThenRecordStorage.defaults,
      key: clearThenRecordStorage.key,
      maximumCapacity: 10
    )

    try await clearThenRecord.clearHistory()
    let recorded = try await clearThenRecord.recordSuccessfulQuery("Swift")
    #expect(recorded == [SearchHistoryEntry(query: "Swift")])
    #expect(try await clearThenRecord.loadHistory() == recorded)
  }

  @Test("Cancellation before commit leaves persisted bytes unchanged")
  func cancellationBeforeCommitLeavesBytesUnchanged() async {
    let persistence = ControlledSearchHistoryPersistence(
      setBehavior: .cancelBeforeCommit
    )
    let repository = UserDefaultsSearchHistoryRepository(
      persistence: persistence,
      key: "history",
      maximumCapacity: 10
    )
    let task = Task {
      try await repository.recordSuccessfulQuery("Swift")
    }

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    #expect(persistence.persistedData() == nil)
  }

  @Test("Cancellation after commit keeps bytes and authoritative result")
  func cancellationAfterCommitKeepsBytes() async throws {
    let persistence = ControlledSearchHistoryPersistence(
      setBehavior: .cancelAfterCommit
    )
    let repository = UserDefaultsSearchHistoryRepository(
      persistence: persistence,
      key: "history",
      maximumCapacity: 10
    )

    let result = try await Task {
      try await repository.recordSuccessfulQuery("Swift")
    }.value

    #expect(result == [SearchHistoryEntry(query: "Swift")])
    let data = try #require(persistence.persistedData())
    #expect(try JSONDecoder().decode([String].self, from: data) == ["Swift"])
  }
}

private struct SearchHistoryStorage {
  let defaults: UserDefaults
  let suiteName: String
  let key = "history"

  func cleanup() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private func makeStorage() throws -> SearchHistoryStorage {
  let suiteName = "SearchHistoryPersistenceTests.\(UUID().uuidString)"
  return SearchHistoryStorage(
    defaults: try #require(UserDefaults(suiteName: suiteName)),
    suiteName: suiteName
  )
}

private final class ControlledSearchHistoryPersistence:
  SearchHistoryPersistence,
  @unchecked Sendable
{
  enum SetBehavior: Equatable, Sendable {
    case cancelBeforeCommit
    case cancelAfterCommit
  }

  private let setBehavior: SetBehavior
  private var data: Data?

  init(setBehavior: SetBehavior) {
    self.setBehavior = setBehavior
  }

  func data(forKey key: String) throws -> Data? {
    data
  }

  func set(_ data: Data, forKey key: String) throws {
    if setBehavior == .cancelBeforeCommit {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      try Task.checkCancellation()
    }

    self.data = data
    if setBehavior == .cancelAfterCommit {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
  }

  func removeObject(forKey key: String) throws {
    data = nil
  }

  func persistedData() -> Data? {
    data
  }
}

private final class ReentrantReadSearchHistoryPersistence:
  SearchHistoryPersistence,
  @unchecked Sendable
{
  private let asynchronousState = ReentrantReadState()
  private var synchronousData: Data?

  func data(forKey key: String) throws -> Data? {
    synchronousData
  }

  func set(_ data: Data, forKey key: String) throws {
    synchronousData = data
  }

  func removeObject(forKey key: String) throws {
    synchronousData = nil
  }

  func data(forKey key: String) async throws -> Data? {
    await asynchronousState.dataAfterConcurrentRead()
  }

  func set(_ data: Data, forKey key: String) async throws {
    await asynchronousState.set(data)
  }

  func removeObject(forKey key: String) async throws {
    await asynchronousState.removeData()
  }
}

private actor ReentrantReadState {
  private var data: Data?
  private var firstRead: CheckedContinuation<Data?, Never>?

  func dataAfterConcurrentRead() async -> Data? {
    guard let firstRead else {
      return await withCheckedContinuation { continuation in
        self.firstRead = continuation
      }
    }

    self.firstRead = nil
    firstRead.resume(returning: data)
    return data
  }

  func set(_ data: Data) {
    self.data = data
  }

  func removeData() {
    data = nil
  }
}
