import Foundation
import Observation

@MainActor
@Observable
final class FavoritesViewModel {
  private(set) var state: FavoritesViewState = .initializing

  @ObservationIgnored private let repository: RepositoriesRepository
  @ObservationIgnored private let favoritesStore: FavoritesStore
  @ObservationIgnored private let concurrencyLimit: Int
  @ObservationIgnored private var summaries: [Int: RepositorySummary] = [:]
  @ObservationIgnored private var failedRepositoryIDs: Set<Int> = []
  @ObservationIgnored private var lastError: AppError?
  @ObservationIgnored private var requestedRepositoryIDs: Set<Int>?
  @ObservationIgnored private var activeLoadIdentity: ActiveLoadIdentity?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  init(
    repository: RepositoriesRepository,
    favoritesStore: FavoritesStore,
    concurrencyLimit: Int = 4
  ) {
    self.repository = repository
    self.favoritesStore = favoritesStore
    self.concurrencyLimit = max(1, concurrencyLimit)
  }

  deinit {
    loadTask?.cancel()
  }

  var favoritesAreLoaded: Bool {
    favoritesStore.isLoaded
  }

  var favoriteRepositoryIDs: Set<Int> {
    favoritesStore.favoriteRepositoryIDs
  }

  var visibleRepositories: [RepositorySummary] {
    repositories(in: state).filter { favoriteRepositoryIDs.contains($0.id) }
  }

  func loadFavorites() async {
    await favoritesStore.load()
  }

  func synchronize() {
    guard favoritesStore.isLoaded else {
      state = .initializing
      return
    }

    let ids = favoritesStore.favoriteRepositoryIDs
    guard !ids.isEmpty else {
      cancelLoad()
      requestedRepositoryIDs = ids
      failedRepositoryIDs = []
      state = .empty
      return
    }

    let missingIDs = ids.subtracting(summaries.keys)
    let requiredIDs = missingIDs.union(failedRepositoryIDs.intersection(ids))

    if requiredIDs.isEmpty {
      cancelLoad()
      requestedRepositoryIDs = ids
      renderLoaded(ids: ids, failedIDs: [])
      return
    }

    guard requestedRepositoryIDs != ids || loadTask == nil else {
      return
    }

    startLoad(
      ids: ids,
      requestedIDs: requiredIDs,
      kind: .membership
    )
  }

  func refresh() async {
    guard favoritesStore.isLoaded else {
      return
    }

    let ids = favoritesStore.favoriteRepositoryIDs
    guard !ids.isEmpty else {
      synchronize()
      return
    }

    startLoad(ids: ids, requestedIDs: ids, kind: .refresh)
    await loadTask?.value
  }

  func retry() {
    guard favoritesStore.isLoaded else {
      return
    }

    let ids = favoritesStore.favoriteRepositoryIDs
    let retryIDs = failedRepositoryIDs.intersection(ids)
    startLoad(
      ids: ids,
      requestedIDs: retryIDs.isEmpty ? ids : retryIDs,
      kind: .retry
    )
  }

  func toggleFavorite(repositoryID: Int) {
    favoritesStore.toggle(repositoryID: repositoryID)
  }

  func isUpdating(repositoryID: Int) -> Bool {
    favoritesStore.isUpdating(repositoryID: repositoryID)
  }

  func cancel() {
    cancelLoad()
    renderAfterCancellation()
  }

  private func startLoad(
    ids: Set<Int>,
    requestedIDs: Set<Int>,
    kind: LoadKind
  ) {
    guard !requestedIDs.isEmpty else {
      renderLoaded(ids: ids, failedIDs: [])
      return
    }

    let identity = ActiveLoadIdentity(ids: requestedIDs, kind: kind)
    guard activeLoadIdentity != identity else {
      return
    }

    loadTask?.cancel()
    generation += 1
    let requestGeneration = generation
    requestedRepositoryIDs = ids
    activeLoadIdentity = identity

    if summaries.isEmpty {
      state = .loading
    } else {
      renderLoaded(
        ids: ids,
        failedIDs: failedRepositoryIDs,
        isRefreshing: kind != .membership,
        countMissingAsFailure: false
      )
    }

    let repository = repository
    let limit = concurrencyLimit
    loadTask = Task { [weak self] in
      let results = await Self.loadRepositories(
        ids: requestedIDs,
        repository: repository,
        concurrencyLimit: limit
      )
      guard !Task.isCancelled else {
        self?.finishCancellation(generation: requestGeneration)
        return
      }
      self?.apply(results: results, generation: requestGeneration)
    }
  }

  private func apply(
    results: [Int: Result<RepositorySummary, AppError>],
    generation requestGeneration: Int
  ) {
    guard generation == requestGeneration else {
      return
    }

    let currentIDs = favoritesStore.favoriteRepositoryIDs
    var failures: Set<Int> = []
    var hasCancellation = false

    for (id, result) in results where currentIDs.contains(id) {
      switch result {
      case .success(let repository):
        summaries[id] = repository
      case .failure(let error):
        if error == .cancelled {
          hasCancellation = true
        } else {
          failures.insert(id)
        }
      }
    }

    failedRepositoryIDs = failures
    let errors: [AppError] = results.keys.sorted().compactMap { id in
      guard
        case .failure(let error) = results[id],
        error != .cancelled
      else {
        return nil
      }
      return error
    }
    lastError = errors.first
    loadTask = nil
    activeLoadIdentity = nil
    requestedRepositoryIDs = currentIDs
    if hasCancellation {
      renderAfterCancellation()
    } else {
      renderLoaded(ids: currentIDs, failedIDs: failures)
    }
  }

  private func finishCancellation(generation requestGeneration: Int) {
    guard generation == requestGeneration else {
      return
    }

    loadTask = nil
    activeLoadIdentity = nil
    renderAfterCancellation()
  }

  private func renderAfterCancellation() {
    guard favoritesStore.isLoaded else {
      state = .initializing
      return
    }

    let ids = favoritesStore.favoriteRepositoryIDs
    if ids.isEmpty {
      state = .empty
    } else if summaries.keys.contains(where: ids.contains) {
      renderLoaded(
        ids: ids,
        failedIDs: failedRepositoryIDs,
        countMissingAsFailure: false
      )
    } else {
      state = .idle
    }
  }

  private func renderLoaded(
    ids: Set<Int>,
    failedIDs: Set<Int>,
    isRefreshing: Bool = false,
    countMissingAsFailure: Bool = true
  ) {
    let repositories = sortedRepositories(ids.compactMap { summaries[$0] })
    let missingCount = ids.subtracting(repositories.map(\.id)).count
    let failureCount = countMissingAsFailure
      ? max(failedIDs.intersection(ids).count, missingCount)
      : failedIDs.intersection(ids).count

    if repositories.isEmpty {
      state = ids.isEmpty ? .empty : .failed(lastError ?? .unknown)
    } else {
      state = .loaded(
        repositories: repositories,
        failedCount: failureCount,
        isRefreshing: isRefreshing
      )
    }
  }

  private func repositories(in state: FavoritesViewState) -> [RepositorySummary] {
    guard case .loaded(let repositories, _, _) = state else {
      return []
    }
    return repositories
  }

  private func sortedRepositories(_ repositories: [RepositorySummary]) -> [RepositorySummary] {
    repositories.sorted {
      $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
    }
  }

  private func cancelLoad() {
    generation += 1
    loadTask?.cancel()
    loadTask = nil
    activeLoadIdentity = nil
  }

  nonisolated private static func loadRepositories(
    ids: Set<Int>,
    repository: RepositoriesRepository,
    concurrencyLimit: Int
  ) async -> [Int: Result<RepositorySummary, AppError>] {
    let orderedIDs = ids.sorted()
    var iterator = orderedIDs.makeIterator()

    return await withTaskGroup(
      of: (Int, Result<RepositorySummary, AppError>).self,
      returning: [Int: Result<RepositorySummary, AppError>].self
    ) { group in
      for _ in 0..<min(concurrencyLimit, orderedIDs.count) {
        guard let id = iterator.next() else {
          break
        }
        group.addTask {
          await loadRepository(id: id, repository: repository)
        }
      }

      var results: [Int: Result<RepositorySummary, AppError>] = [:]
      for await (id, result) in group {
        results[id] = result
        if !Task.isCancelled, let nextID = iterator.next() {
          group.addTask {
            await loadRepository(id: nextID, repository: repository)
          }
        }
      }
      return results
    }
  }

  nonisolated private static func loadRepository(
    id: Int,
    repository: RepositoriesRepository
  ) async -> (Int, Result<RepositorySummary, AppError>) {
    do {
      return (id, .success(try await repository.repository(id: id)))
    } catch let error as AppError {
      return (id, .failure(error))
    } catch is CancellationError {
      return (id, .failure(.cancelled))
    } catch {
      return (id, .failure(.unknown))
    }
  }
}

private extension FavoritesViewModel {
  enum LoadKind: Equatable {
    case membership
    case refresh
    case retry
  }

  struct ActiveLoadIdentity: Equatable {
    let ids: Set<Int>
    let kind: LoadKind
  }
}
