import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
  private(set) var state = RepositorySearchViewState()
  private(set) var historyState: SearchHistoryViewState = .idle

  let minimumQueryLength: Int
  let favoritesStore: FavoritesStore

  @ObservationIgnored private let repository: RepositoriesRepository
  @ObservationIgnored private let historyRepository: (any SearchHistoryRepository)?
  @ObservationIgnored private let perPage: Int
  @ObservationIgnored private let debounceDuration: Duration
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var paginationTask: Task<Void, Never>?
  @ObservationIgnored private var historyTask: Task<Void, Never>?
  @ObservationIgnored private var pendingHistoryOperations: [SearchHistoryOperation] = []
  @ObservationIgnored private var activeHistoryOperation: SearchHistoryOperation?
  @ObservationIgnored private var didRequestHistoryLoad = false
  @ObservationIgnored private var activeRequestID = 0
  @ObservationIgnored private var currentPage: Int?
  @ObservationIgnored private var pageInFlight: Int?
  @ObservationIgnored private var hasNextPage = false

  init(
    repository: RepositoriesRepository,
    favoritesStore: FavoritesStore,
    historyRepository: (any SearchHistoryRepository)? = nil,
    minimumQueryLength: Int = 3,
    perPage: Int = 30,
    debounceDuration: Duration = .milliseconds(350)
  ) {
    self.repository = repository
    self.favoritesStore = favoritesStore
    self.historyRepository = historyRepository
    self.minimumQueryLength = minimumQueryLength
    self.perPage = perPage
    self.debounceDuration = debounceDuration
  }

  deinit {
    searchTask?.cancel()
    paginationTask?.cancel()
    historyTask?.cancel()
  }

  func loadSearchHistory() {
    guard historyRepository != nil, !didRequestHistoryLoad else {
      return
    }
    didRequestHistoryLoad = true
    enqueueHistoryOperation(.load)
  }

  func clearSearchHistory() {
    guard historyRepository != nil else {
      return
    }
    enqueueHistoryOperation(.clear)
  }

  func retrySearchHistory() {
    guard case .failed(_, _, let operation) = historyState else {
      return
    }
    enqueueHistoryOperation(operation)
  }

  func selectSearchHistoryEntry(_ entry: SearchHistoryEntry) {
    state.query = entry.query
    startImmediateInitialSearch(query: entry.query)
  }

  func loadFavorites() async {
    await favoritesStore.load()
  }

  var favoritesAreLoaded: Bool {
    favoritesStore.isLoaded
  }

  func isFavorite(repositoryID: Int) -> Bool {
    favoritesStore.isFavorite(repositoryID: repositoryID)
  }

  func isUpdatingFavorite(repositoryID: Int) -> Bool {
    favoritesStore.isUpdating(repositoryID: repositoryID)
  }

  func toggleFavorite(repositoryID: Int) {
    favoritesStore.toggle(repositoryID: repositoryID)
  }

  func updateQuery(_ query: String) {
    state.query = query
    cancelTasks()
    activeRequestID += 1

    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedQuery.count >= minimumQueryLength else {
      resetSearch()
      state.query = query
      return
    }

    let requestID = activeRequestID
    searchTask = Task { [weak self] in
      do {
        guard let self else {
          return
        }
        try await Task.sleep(for: self.debounceDuration)
        await self.performInitialSearch(query: normalizedQuery, requestID: requestID)
      } catch is CancellationError {
        return
      } catch {
        assertionFailure("Unexpected debounce error: \(error)")
      }
    }
  }

  func retry() {
    let normalizedQuery = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedQuery.count >= minimumQueryLength else {
      return
    }

    if case .failed = state.pagination {
      loadNextPage()
    } else {
      startImmediateInitialSearch(query: normalizedQuery)
    }
  }

  func loadNextPage() {
    guard state.phase == .loaded || state.phase == .failed else {
      return
    }

    guard hasNextPage else {
      state.pagination = .endReached
      return
    }

    let nextPage = (currentPage ?? 0) + 1
    guard pageInFlight == nil else {
      return
    }

    let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= minimumQueryLength else {
      return
    }

    pageInFlight = nextPage
    state.pagination = .loadingNextPage
    state.error = nil

    let requestID = activeRequestID
    paginationTask?.cancel()
    paginationTask = Task { [weak self] in
      await self?.performNextPageSearch(query: query, page: nextPage, requestID: requestID)
    }
  }

  private func performInitialSearch(query: String, requestID: Int) async {
    guard requestID == activeRequestID else {
      return
    }

    currentPage = nil
    pageInFlight = 1
    hasNextPage = false
    state.items = []
    state.phase = .initialLoading
    state.pagination = .idle
    state.error = nil
    state.isShowingIncompleteResults = false

    do {
      let page = try await repository.searchRepositories(query: query, page: 1, perPage: perPage)
      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pageInFlight = nil
      currentPage = page.currentPage
      hasNextPage = page.hasNextPage
      state.query = query
      state.items = page.items
      state.phase = page.items.isEmpty ? .empty : .loaded
      state.pagination = page.hasNextPage ? .idle : .endReached
      state.error = nil
      state.isShowingIncompleteResults = page.isIncomplete
      if historyRepository != nil {
        enqueueHistoryOperation(.record(query))
      }
      searchTask = nil
    } catch {
      if isCancellation(error) {
        applyInitialCancellation(query: query, requestID: requestID)
        return
      }

      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pageInFlight = nil
      state.query = query
      state.items = []
      state.phase = .failed
      state.pagination = .idle
      state.error = mapError(error)
      state.isShowingIncompleteResults = false
      searchTask = nil
    }
  }

  private func performNextPageSearch(query: String, page: Int, requestID: Int) async {
    do {
      let repositoryPage = try await repository.searchRepositories(query: query, page: page, perPage: perPage)
      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pageInFlight = nil
      currentPage = repositoryPage.currentPage
      hasNextPage = repositoryPage.hasNextPage

      let existingIDs = Set(state.items.map(\.id))
      let newItems = repositoryPage.items.filter { !existingIDs.contains($0.id) }
      state.items.append(contentsOf: newItems)
      state.phase = state.items.isEmpty ? .empty : .loaded
      state.pagination = repositoryPage.hasNextPage ? .idle : .endReached
      state.error = nil
      state.isShowingIncompleteResults =
        state.isShowingIncompleteResults || repositoryPage.isIncomplete
      paginationTask = nil
    } catch {
      if isCancellation(error) {
        applyPaginationCancellation(query: query, requestID: requestID)
        return
      }

      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pageInFlight = nil
      state.phase = state.items.isEmpty ? .failed : .loaded
      state.pagination = .failed(mapError(error))
      paginationTask = nil
    }
  }

  private func applyInitialCancellation(query: String, requestID: Int) {
    guard matchesActiveRequest(query: query, requestID: requestID) else {
      return
    }

    currentPage = nil
    pageInFlight = nil
    hasNextPage = false
    state = RepositorySearchViewState(query: state.query)
    searchTask = nil
  }

  private func applyPaginationCancellation(query: String, requestID: Int) {
    guard matchesActiveRequest(query: query, requestID: requestID) else {
      return
    }

    pageInFlight = nil
    state.phase = state.items.isEmpty ? .idle : .loaded
    state.pagination = .idle
    state.error = nil
    paginationTask = nil
  }

  private func resetSearch() {
    currentPage = nil
    pageInFlight = nil
    hasNextPage = false
    state = RepositorySearchViewState()
  }

  private func startImmediateInitialSearch(query: String) {
    cancelTasks()
    activeRequestID += 1
    let requestID = activeRequestID
    searchTask = Task { [weak self] in
      await self?.performInitialSearch(query: query, requestID: requestID)
    }
  }

  private func cancelTasks() {
    searchTask?.cancel()
    paginationTask?.cancel()
    searchTask = nil
    paginationTask = nil
  }

  private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || error as? AppError == .cancelled
  }

  private func shouldApplyResponse(query: String, requestID: Int) -> Bool {
    !Task.isCancelled && matchesActiveRequest(query: query, requestID: requestID)
  }

  private func matchesActiveRequest(query: String, requestID: Int) -> Bool {
    requestID == activeRequestID
      && state.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
  }

  private func mapError(_ error: Error) -> AppError {
    if let appError = error as? AppError {
      return appError
    }

    if error is CancellationError {
      return .cancelled
    }

    return .unknown
  }

  private func enqueueHistoryOperation(_ operation: SearchHistoryOperation) {
    pendingHistoryOperations.append(operation)
    startNextHistoryOperationIfNeeded()
  }

  private func startNextHistoryOperationIfNeeded() {
    guard
      activeHistoryOperation == nil,
      let operation = pendingHistoryOperations.first,
      let historyRepository
    else {
      return
    }

    activeHistoryOperation = operation
    let entries = currentHistoryEntries
    switch operation {
    case .load where entries.isEmpty:
      historyState = .loading
    case .load, .record, .clear:
      historyState = .updating(entries, operation)
    }

    historyTask = Task { [weak self, historyRepository] in
      let result = await Self.executeHistoryOperation(
        operation,
        repository: historyRepository
      )
      guard !Task.isCancelled else {
        return
      }
      self?.completeHistoryOperation(operation, result: result)
    }
  }

  private func completeHistoryOperation(
    _ operation: SearchHistoryOperation,
    result: SearchHistoryOperationResult
  ) {
    guard
      activeHistoryOperation == operation,
      pendingHistoryOperations.first == operation
    else {
      return
    }

    let preservedEntries = currentHistoryEntries
    historyTask = nil
    activeHistoryOperation = nil
    pendingHistoryOperations.removeFirst()

    switch result {
    case .entries(let entries):
      historyState = .loaded(entries)
    case .cleared:
      historyState = .loaded([])
    case .failure(let error):
      historyState = .failed(preservedEntries, error, operation)
    case .cancelled:
      historyState = preservedEntries.isEmpty
        ? .idle
        : .loaded(preservedEntries)
    }

    startNextHistoryOperationIfNeeded()
  }

  private var currentHistoryEntries: [SearchHistoryEntry] {
    switch historyState {
    case .loaded(let entries),
      .updating(let entries, _),
      .failed(let entries, _, _):
      entries
    case .idle, .loading:
      []
    }
  }

  nonisolated private static func executeHistoryOperation(
    _ operation: SearchHistoryOperation,
    repository: any SearchHistoryRepository
  ) async -> SearchHistoryOperationResult {
    do {
      try Task.checkCancellation()
      switch operation {
      case .load:
        return .entries(try await repository.loadHistory())
      case .record(let query):
        return .entries(
          try await repository.recordSuccessfulQuery(query)
        )
      case .clear:
        try await repository.clearHistory()
        return .cleared
      }
    } catch is CancellationError {
      return .cancelled
    } catch AppError.cancelled {
      return .cancelled
    } catch let error as AppError {
      return .failure(error)
    } catch {
      assertionFailure("SearchHistoryRepository leaked a raw error: \(error)")
      return .failure(.unknown)
    }
  }
}

nonisolated private enum SearchHistoryOperationResult: Sendable {
  case entries([SearchHistoryEntry])
  case cleared
  case failure(AppError)
  case cancelled
}
