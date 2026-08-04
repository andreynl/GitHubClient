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

  @Test("Cancellation before commit leaves persisted bytes unchanged")
  func cancellationBeforeCommitLeavesBytesUnchanged() async {
    let persistence = ControlledSearchHistoryPersistence(
      setBehavior: .suspendBeforeCommit
    )
    let repository = UserDefaultsSearchHistoryRepository(
      persistence: persistence,
      key: "history",
      maximumCapacity: 10
    )
    let task = Task {
      try await repository.recordSuccessfulQuery("Swift")
    }

    await persistence.waitForSetInvocation()
    task.cancel()
    await persistence.releaseSet()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    #expect(await persistence.persistedData() == nil)
    #expect(await persistence.outstandingOperationCount() == 0)
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
    let data = try #require(await persistence.persistedData())
    #expect(try JSONDecoder().decode([String].self, from: data) == ["Swift"])
    #expect(await persistence.outstandingOperationCount() == 0)
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

private actor ControlledSearchHistoryPersistence: SearchHistoryPersistence {
  enum SetBehavior: Equatable, Sendable {
    case suspendBeforeCommit
    case cancelAfterCommit
  }

  private let setBehavior: SetBehavior
  private var data: Data?
  private var setInvocationCount = 0
  private var setInvocationWaiters: [CheckedContinuation<Void, Never>] = []
  private var setContinuation: CheckedContinuation<Void, Never>?

  init(setBehavior: SetBehavior) {
    self.setBehavior = setBehavior
  }

  func data(forKey key: String) async throws -> Data? {
    data
  }

  func set(_ data: Data, forKey key: String) async throws {
    setInvocationCount += 1
    let waiters = setInvocationWaiters
    setInvocationWaiters.removeAll()
    waiters.forEach { $0.resume() }

    if setBehavior == .suspendBeforeCommit {
      await withCheckedContinuation { continuation in
        setContinuation = continuation
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

  func removeObject(forKey key: String) async throws {
    data = nil
  }

  func waitForSetInvocation() async {
    guard setInvocationCount == 0 else {
      return
    }
    await withCheckedContinuation { continuation in
      setInvocationWaiters.append(continuation)
    }
  }

  func releaseSet() {
    setContinuation?.resume()
    setContinuation = nil
  }

  func persistedData() -> Data? {
    data
  }

  func outstandingOperationCount() -> Int {
    setContinuation == nil ? 0 : 1
  }
}
