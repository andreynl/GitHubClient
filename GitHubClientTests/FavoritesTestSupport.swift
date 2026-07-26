import Foundation
import Testing

@testable import GitHubClient

enum FavoriteTestError: Error, Sendable {
  case failure
}

enum FavoriteReadBehavior: Sendable {
  case success(delay: Duration = .zero)
  case failure
  case cancellation
}

enum FavoriteWriteBehavior: Sendable {
  case success(delay: Duration = .zero)
  case failure(delay: Duration = .zero)
  case cancellation(delay: Duration = .zero)
  case controlled
  case suspendUntilCancelled
}

enum FavoriteControlledWriteResult: Sendable {
  case success
  case failure
  case cancellation
}

struct FavoriteWriteCall: Equatable, Sendable {
  let repositoryID: Int
  let isFavorite: Bool
}

actor InMemoryFavoritesRepository: FavoritesRepository {
  private struct ControlledWrite {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var ids: Set<Int>
  private let readBehavior: FavoriteReadBehavior
  private var writeBehaviors: [Int: [FavoriteWriteBehavior]]
  private var reads = 0
  private var calls: [FavoriteWriteCall] = []
  private var activeWrites: [Int: Int] = [:]
  private var maximumWrites: [Int: Int] = [:]
  private var cancelledWrites = 0
  private var controlledWrites: [Int: [ControlledWrite]] = [:]

  init(
    ids: Set<Int> = [],
    readBehavior: FavoriteReadBehavior = .success(),
    writeBehaviors: [Int: [FavoriteWriteBehavior]] = [:]
  ) {
    self.ids = ids
    self.readBehavior = readBehavior
    self.writeBehaviors = writeBehaviors
  }

  func favoriteRepositoryIDs() async throws -> Set<Int> {
    reads += 1

    switch readBehavior {
    case .success(let delay):
      try await Task.sleep(for: delay)
      return ids
    case .failure:
      throw FavoriteTestError.failure
    case .cancellation:
      throw CancellationError()
    }
  }

  func setFavorite(_ isFavorite: Bool, repositoryID: Int) async throws {
    let call = FavoriteWriteCall(repositoryID: repositoryID, isFavorite: isFavorite)
    calls.append(call)
    activeWrites[repositoryID, default: 0] += 1
    maximumWrites[repositoryID] = max(
      maximumWrites[repositoryID, default: 0],
      activeWrites[repositoryID, default: 0]
    )
    defer {
      activeWrites[repositoryID, default: 0] -= 1
    }

    let behavior = nextWriteBehavior(repositoryID: repositoryID)
    switch behavior {
    case .success(let delay):
      try await Task.sleep(for: delay)
      setPersistedValue(isFavorite, repositoryID: repositoryID)
    case .failure(let delay):
      try await Task.sleep(for: delay)
      throw FavoriteTestError.failure
    case .cancellation(let delay):
      try await Task.sleep(for: delay)
      throw CancellationError()
    case .controlled:
      try await waitForControlledWrite(repositoryID: repositoryID)
      setPersistedValue(isFavorite, repositoryID: repositoryID)
    case .suspendUntilCancelled:
      do {
        try await Task.sleep(for: .seconds(3_600))
      } catch is CancellationError {
        cancelledWrites += 1
        throw CancellationError()
      }
    }
  }

  func readCount() -> Int {
    reads
  }

  func writeCalls() -> [FavoriteWriteCall] {
    calls
  }

  func maximumConcurrentWrites(for repositoryID: Int) -> Int {
    maximumWrites[repositoryID, default: 0]
  }

  func cancelledWriteCount() -> Int {
    cancelledWrites
  }

  func completeNextControlledWrite(
    repositoryID: Int,
    result: FavoriteControlledWriteResult
  ) -> Bool {
    guard
      var continuations = controlledWrites[repositoryID],
      !continuations.isEmpty
    else {
      return false
    }

    let controlledWrite = continuations.removeFirst()
    controlledWrites[repositoryID] = continuations

    switch result {
    case .success:
      controlledWrite.continuation.resume()
    case .failure:
      controlledWrite.continuation.resume(throwing: FavoriteTestError.failure)
    case .cancellation:
      controlledWrite.continuation.resume(throwing: CancellationError())
    }

    return true
  }

  func pendingControlledWriteCount() -> Int {
    controlledWrites.values.reduce(0) { $0 + $1.count }
  }

  private func waitForControlledWrite(repositoryID: Int) async throws {
    let controlledWriteID = UUID()

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }

        controlledWrites[repositoryID, default: []].append(
          ControlledWrite(
            id: controlledWriteID,
            continuation: continuation
          )
        )
      }
    } onCancel: {
      Task {
        await self.cancelControlledWrite(
          id: controlledWriteID,
          repositoryID: repositoryID
        )
      }
    }
  }

  private func cancelControlledWrite(id: UUID, repositoryID: Int) {
    guard
      var controlledWritesForRepository = controlledWrites[repositoryID],
      let index = controlledWritesForRepository.firstIndex(where: { $0.id == id })
    else {
      return
    }

    let controlledWrite = controlledWritesForRepository.remove(at: index)
    controlledWrites[repositoryID] = controlledWritesForRepository
    controlledWrite.continuation.resume(throwing: CancellationError())
  }

  private func nextWriteBehavior(repositoryID: Int) -> FavoriteWriteBehavior {
    guard var behaviors = writeBehaviors[repositoryID], !behaviors.isEmpty else {
      return .success()
    }

    let behavior = behaviors.removeFirst()
    writeBehaviors[repositoryID] = behaviors
    return behavior
  }

  private func setPersistedValue(_ isFavorite: Bool, repositoryID: Int) {
    if isFavorite {
      ids.insert(repositoryID)
    } else {
      ids.remove(repositoryID)
    }
  }
}

@MainActor
func makeFavoritesStore(ids: Set<Int> = []) -> FavoritesStore {
  FavoritesStore(repository: InMemoryFavoritesRepository(ids: ids))
}

@MainActor
func waitForFavorites(
  timeout: Duration = .seconds(1),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let start = ContinuousClock.now
  while !condition() {
    if ContinuousClock.now - start > timeout {
      Issue.record("Timed out waiting for favorite state")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

func waitForAsync(
  timeout: Duration = .seconds(1),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let start = ContinuousClock.now
  while !(await condition()) {
    if ContinuousClock.now - start > timeout {
      Issue.record("Timed out waiting for asynchronous favorite condition")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}
