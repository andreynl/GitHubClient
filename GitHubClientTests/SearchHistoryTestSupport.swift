import Foundation
import Observation

@testable import GitHubClient

enum ControlledSearchHistoryResult: Sendable {
  case success([SearchHistoryEntry])
  case failure(AppError)
  case cancellation
}

enum ControlledInitialSearchResult: Sendable {
  case success(RepositoryPage)
  case failure(AppError)
  case cancellation
}

nonisolated struct SearchHistoryRepositoryStub: SearchHistoryRepository {
  func loadHistory() async throws -> [SearchHistoryEntry] {
    []
  }

  func recordSuccessfulQuery(_ query: String) async throws
    -> [SearchHistoryEntry] {
    []
  }

  func clearHistory() async throws {}
}

actor ControlledInitialSearchRepository: RepositoriesRepository {
  private struct PendingSearch {
    let query: String
    let continuation: CheckedContinuation<RepositoryPage, any Error>
  }

  private var pendingSearches: [PendingSearch] = []
  private var recordedQueries: [String] = []
  private var invocationWaiters: [
    Int: [CheckedContinuation<Void, Never>]
  ] = [:]

  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage {
    recordedQueries.append(query)
    resumeInvocationWaiters()
    return try await withCheckedThrowingContinuation { continuation in
      pendingSearches.append(
        PendingSearch(query: query, continuation: continuation)
      )
    }
  }

  func repositoryDetails(
    owner: String,
    name: String
  ) async throws -> RepositoryDetails {
    throw AppError.unknown
  }

  func repository(id: Int) async throws -> RepositorySummary {
    throw AppError.unknown
  }

  func repositoryReadme(
    owner: String,
    name: String
  ) async throws -> RepositoryReadme {
    throw AppError.unknown
  }

  func waitForInvocationCount(_ count: Int) async {
    guard recordedQueries.count < count else {
      return
    }
    await withCheckedContinuation { continuation in
      invocationWaiters[count, default: []].append(continuation)
    }
  }

  func queries() -> [String] {
    recordedQueries
  }

  func complete(
    query: String,
    with result: ControlledInitialSearchResult
  ) -> Bool {
    guard
      let index = pendingSearches.firstIndex(where: { $0.query == query })
    else {
      return false
    }
    let pending = pendingSearches.remove(at: index)
    switch result {
    case .success(let page):
      pending.continuation.resume(returning: page)
    case .failure(let error):
      pending.continuation.resume(throwing: error)
    case .cancellation:
      pending.continuation.resume(throwing: CancellationError())
    }
    return true
  }

  func outstandingOperationCount() -> Int {
    pendingSearches.count
  }

  private func resumeInvocationWaiters() {
    let readyCounts = invocationWaiters.keys.filter {
      $0 <= recordedQueries.count
    }
    for count in readyCounts {
      invocationWaiters.removeValue(forKey: count)?.forEach { $0.resume() }
    }
  }
}

nonisolated struct SearchHistoryPagedRepository: RepositoriesRepository {
  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage {
    RepositoryPage(
      items: [searchHistoryPagedSummary(id: page)],
      currentPage: page,
      hasNextPage: page == 1,
      totalCount: 2
    )
  }

  func repositoryDetails(
    owner: String,
    name: String
  ) async throws -> RepositoryDetails {
    throw AppError.unknown
  }

  func repository(id: Int) async throws -> RepositorySummary {
    throw AppError.unknown
  }

  func repositoryReadme(
    owner: String,
    name: String
  ) async throws -> RepositoryReadme {
    throw AppError.unknown
  }
}

actor ControlledSearchHistoryRepository: SearchHistoryRepository {
  private struct PendingOperation {
    let id: UUID
    let continuation: CheckedContinuation<[SearchHistoryEntry], any Error>
  }

  private var pendingOperations: [PendingOperation] = []
  private var recordedInvocations: [SearchHistoryOperation] = []
  private var invocationWaiters: [
    Int: [CheckedContinuation<Void, Never>]
  ] = [:]
  private var cancellations = 0
  private var cancellationWaiters: [
    Int: [CheckedContinuation<Void, Never>]
  ] = [:]

  func loadHistory() async throws -> [SearchHistoryEntry] {
    try await perform(.load)
  }

  func recordSuccessfulQuery(_ query: String) async throws
    -> [SearchHistoryEntry] {
    try await perform(.record(query))
  }

  func clearHistory() async throws {
    _ = try await perform(.clear)
  }

  func waitForInvocationCount(_ count: Int) async {
    guard recordedInvocations.count < count else {
      return
    }
    await withCheckedContinuation { continuation in
      invocationWaiters[count, default: []].append(continuation)
    }
  }

  func invocations() -> [SearchHistoryOperation] {
    recordedInvocations
  }

  func completeNext(with result: ControlledSearchHistoryResult) -> Bool {
    guard !pendingOperations.isEmpty else {
      return false
    }
    let pending = pendingOperations.removeFirst()
    switch result {
    case .success(let entries):
      pending.continuation.resume(returning: entries)
    case .failure(let error):
      pending.continuation.resume(throwing: error)
    case .cancellation:
      pending.continuation.resume(throwing: CancellationError())
    }
    return true
  }

  func waitForCancellationCount(_ count: Int) async {
    guard cancellations < count else {
      return
    }
    await withCheckedContinuation { continuation in
      cancellationWaiters[count, default: []].append(continuation)
    }
  }

  func outstandingOperationCount() -> Int {
    pendingOperations.count
  }

  func outstandingWaiterCount() -> Int {
    invocationWaiters.values.reduce(0) { $0 + $1.count }
      + cancellationWaiters.values.reduce(0) { $0 + $1.count }
  }

  private func perform(
    _ operation: SearchHistoryOperation
  ) async throws -> [SearchHistoryEntry] {
    let id = UUID()
    recordedInvocations.append(operation)
    resumeInvocationWaiters()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        pendingOperations.append(
          PendingOperation(id: id, continuation: continuation)
        )
      }
    } onCancel: {
      Task {
        await self.cancelOperation(id: id)
      }
    }
  }

  private func resumeInvocationWaiters() {
    let readyCounts = invocationWaiters.keys.filter {
      $0 <= recordedInvocations.count
    }
    for count in readyCounts {
      invocationWaiters.removeValue(forKey: count)?.forEach { $0.resume() }
    }
  }

  private func cancelOperation(id: UUID) {
    guard
      let index = pendingOperations.firstIndex(where: { $0.id == id })
    else {
      return
    }
    cancellations += 1
    let readyCounts = cancellationWaiters.keys.filter {
      $0 <= cancellations
    }
    for count in readyCounts {
      cancellationWaiters.removeValue(forKey: count)?.forEach { $0.resume() }
    }
    pendingOperations.remove(at: index).continuation.resume(
      throwing: CancellationError()
    )
  }
}

nonisolated struct SearchHistoryRepositoriesStub: RepositoriesRepository {
  func searchRepositories(
    query: String,
    page: Int,
    perPage: Int
  ) async throws -> RepositoryPage {
    throw AppError.unknown
  }

  func repositoryDetails(
    owner: String,
    name: String
  ) async throws -> RepositoryDetails {
    throw AppError.unknown
  }

  func repository(id: Int) async throws -> RepositorySummary {
    throw AppError.unknown
  }

  func repositoryReadme(
    owner: String,
    name: String
  ) async throws -> RepositoryReadme {
    throw AppError.unknown
  }
}

@MainActor
func makeSearchHistoryViewModel(
  historyRepository: any SearchHistoryRepository,
  repository: any RepositoriesRepository = SearchHistoryRepositoriesStub(),
  debounceDuration: Duration = .zero
) -> SearchViewModel {
  SearchViewModel(
    repository: repository,
    favoritesStore: makeFavoritesStore(),
    historyRepository: historyRepository,
    debounceDuration: debounceDuration
  )
}

@MainActor
func waitForHistoryState(
  _ viewModel: SearchViewModel,
  where predicate: @escaping (SearchHistoryViewState) -> Bool
) async {
  while !predicate(viewModel.historyState) {
    await withCheckedContinuation { continuation in
      withObservationTracking {
        _ = viewModel.historyState
      } onChange: {
        continuation.resume()
      }
    }
  }
}

@MainActor
func waitForPrimarySearchState(
  _ viewModel: SearchViewModel,
  where predicate: @escaping (RepositorySearchViewState) -> Bool
) async {
  while !predicate(viewModel.state) {
    await withCheckedContinuation { continuation in
      withObservationTracking {
        _ = viewModel.state
      } onChange: {
        continuation.resume()
      }
    }
  }
}

nonisolated private func searchHistoryPagedSummary(
  id: Int
) -> RepositorySummary {
  RepositorySummary(
    id: id,
    name: "repository-\(id)",
    fullName: "owner/repository-\(id)",
    owner: RepositoryOwner(
      id: 1,
      login: "owner",
      avatarURL: nil,
      profileURL: nil
    ),
    description: nil,
    starsCount: 0,
    forksCount: 0,
    language: nil,
    updatedAt: nil,
    repositoryURL: nil
  )
}
