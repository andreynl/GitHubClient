import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
  private(set) var state = RepositorySearchViewState()

  let minimumQueryLength: Int

  @ObservationIgnored private let repository: RepositoriesRepository
  @ObservationIgnored private let perPage: Int
  @ObservationIgnored private let debounceDuration: Duration
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var paginationTask: Task<Void, Never>?
  @ObservationIgnored private var activeRequestID = 0
  @ObservationIgnored private var loadedPages: Set<Int> = []
  @ObservationIgnored private var pagesInFlight: Set<Int> = []
  @ObservationIgnored private var hasNextPage = false

  init(
    repository: RepositoriesRepository,
    minimumQueryLength: Int = 3,
    perPage: Int = 30,
    debounceDuration: Duration = .milliseconds(350)
  ) {
    self.repository = repository
    self.minimumQueryLength = minimumQueryLength
    self.perPage = perPage
    self.debounceDuration = debounceDuration
  }

  deinit {
    searchTask?.cancel()
    paginationTask?.cancel()
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
      cancelTasks()
      activeRequestID += 1
      let requestID = activeRequestID
      searchTask = Task { [weak self] in
        await self?.performInitialSearch(query: normalizedQuery, requestID: requestID)
      }
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

    let nextPage = (loadedPages.max() ?? 0) + 1
    guard !loadedPages.contains(nextPage), !pagesInFlight.contains(nextPage) else {
      return
    }

    let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= minimumQueryLength else {
      return
    }

    pagesInFlight.insert(nextPage)
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

    loadedPages.removeAll()
    pagesInFlight = [1]
    hasNextPage = false
    state.items = []
    state.phase = .initialLoading
    state.pagination = .idle
    state.error = nil
    state.isShowingCachedData = false

    do {
      let page = try await repository.searchRepositories(query: query, page: 1, perPage: perPage)
      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pagesInFlight.remove(1)
      loadedPages = [page.currentPage]
      hasNextPage = page.hasNextPage
      state.query = query
      state.items = page.items
      state.phase = page.items.isEmpty ? .empty : .loaded
      state.pagination = page.hasNextPage ? .idle : .endReached
      state.error = nil
      state.isShowingCachedData = page.isFromCache
    } catch {
      guard !isCancellation(error) else {
        return
      }

      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pagesInFlight.remove(1)
      state.query = query
      state.items = []
      state.phase = .failed
      state.pagination = .idle
      state.error = mapError(error)
      state.isShowingCachedData = false
    }
  }

  private func performNextPageSearch(query: String, page: Int, requestID: Int) async {
    do {
      let repositoryPage = try await repository.searchRepositories(query: query, page: page, perPage: perPage)
      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pagesInFlight.remove(page)
      loadedPages.insert(repositoryPage.currentPage)
      hasNextPage = repositoryPage.hasNextPage

      let existingIDs = Set(state.items.map(\.id))
      let newItems = repositoryPage.items.filter { !existingIDs.contains($0.id) }
      state.items.append(contentsOf: newItems)
      state.phase = state.items.isEmpty ? .empty : .loaded
      state.pagination = repositoryPage.hasNextPage ? .idle : .endReached
      state.error = nil
      state.isShowingCachedData = state.isShowingCachedData && repositoryPage.isFromCache
    } catch {
      guard !isCancellation(error) else {
        return
      }

      guard shouldApplyResponse(query: query, requestID: requestID) else {
        return
      }

      pagesInFlight.remove(page)
      state.phase = state.items.isEmpty ? .failed : .loaded
      state.pagination = .failed(mapError(error))
    }
  }

  private func resetSearch() {
    loadedPages.removeAll()
    pagesInFlight.removeAll()
    hasNextPage = false
    state = RepositorySearchViewState()
  }

  private func cancelTasks() {
    searchTask?.cancel()
    paginationTask?.cancel()
    searchTask = nil
    paginationTask = nil
  }

  private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || error as? AppError == .cancelled || error as? GitHubAPIError == .cancelled
  }

  private func shouldApplyResponse(query: String, requestID: Int) -> Bool {
    !Task.isCancelled && requestID == activeRequestID
      && state.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
  }

  private func mapError(_ error: Error) -> AppError {
    if let appError = error as? AppError {
      return appError
    }

    if let apiError = error as? GitHubAPIError {
      return apiError.appError
    }

    if error is CancellationError {
      return .cancelled
    }

    return .unknown(error.localizedDescription)
  }
}
