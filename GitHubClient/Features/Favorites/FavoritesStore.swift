import Observation

@MainActor
@Observable
final class FavoritesStore {
  private(set) var favoriteRepositoryIDs: Set<Int> = []
  private(set) var pendingRepositoryIDs: Set<Int> = []
  private(set) var isLoaded = false

  @ObservationIgnored private let repository: FavoritesRepository
  @ObservationIgnored private var persistedRepositoryIDs: Set<Int> = []
  @ObservationIgnored private var desiredValues: [Int: Bool] = [:]
  @ObservationIgnored private var versions: [Int: Int] = [:]
  @ObservationIgnored private var writeTasks: [Int: Task<Void, Never>] = [:]
  @ObservationIgnored private var loadTask: Task<Set<Int>, Never>?

  init(repository: FavoritesRepository) {
    self.repository = repository
  }

  deinit {
    loadTask?.cancel()
    writeTasks.values.forEach { $0.cancel() }
  }

  func load() async {
    guard !isLoaded else {
      return
    }

    if let loadTask {
      let ids = await loadTask.value
      applyLoadedIDs(ids)
      return
    }

    let repository = repository
    let task = Task<Set<Int>, Never> {
      do {
        return try await repository.favoriteRepositoryIDs()
      } catch {
        return []
      }
    }
    loadTask = task

    let ids = await task.value
    applyLoadedIDs(ids)
  }

  func isFavorite(repositoryID: Int) -> Bool {
    favoriteRepositoryIDs.contains(repositoryID)
  }

  func isUpdating(repositoryID: Int) -> Bool {
    pendingRepositoryIDs.contains(repositoryID)
  }

  func toggle(repositoryID: Int) {
    guard isLoaded else {
      return
    }

    let desiredValue = !favoriteRepositoryIDs.contains(repositoryID)
    setOptimisticValue(desiredValue, repositoryID: repositoryID)
    startWriteIfNeeded(repositoryID: repositoryID)
  }

  private func applyLoadedIDs(_ ids: Set<Int>) {
    guard !isLoaded else {
      return
    }

    persistedRepositoryIDs = ids
    favoriteRepositoryIDs = ids
    isLoaded = true
    loadTask = nil
  }

  private func setOptimisticValue(_ isFavorite: Bool, repositoryID: Int) {
    if isFavorite {
      favoriteRepositoryIDs.insert(repositoryID)
    } else {
      favoriteRepositoryIDs.remove(repositoryID)
    }

    desiredValues[repositoryID] = isFavorite
    versions[repositoryID, default: 0] += 1
    pendingRepositoryIDs.insert(repositoryID)
  }

  private func startWriteIfNeeded(repositoryID: Int) {
    guard writeTasks[repositoryID] == nil else {
      return
    }

    let repository = repository
    writeTasks[repositoryID] = Task { [weak self] in
      while !Task.isCancelled {
        guard let operation = self?.nextWrite(repositoryID: repositoryID) else {
          return
        }

        let result: Result<Void, Error>
        do {
          try await repository.setFavorite(
            operation.isFavorite,
            repositoryID: repositoryID
          )
          result = .success(())
        } catch {
          result = .failure(error)
        }

        guard
          self?.applyWriteResult(
            result,
            isFavorite: operation.isFavorite,
            repositoryID: repositoryID,
            version: operation.version
          ) == true
        else {
          return
        }
      }
    }
  }

  private func nextWrite(repositoryID: Int) -> (isFavorite: Bool, version: Int)? {
    guard
      let isFavorite = desiredValues[repositoryID],
      let version = versions[repositoryID]
    else {
      writeTasks[repositoryID] = nil
      return nil
    }

    return (isFavorite, version)
  }

  private func applyWriteResult(
    _ result: Result<Void, Error>,
    isFavorite: Bool,
    repositoryID: Int,
    version: Int
  ) -> Bool {
    switch result {
    case .success:
      applyWriteSuccess(
        isFavorite,
        repositoryID: repositoryID,
        version: version
      )
    case .failure:
      applyWriteFailure(repositoryID: repositoryID, version: version)
    }

    guard versions[repositoryID] != version, desiredValues[repositoryID] != nil else {
      writeTasks[repositoryID] = nil
      return false
    }

    return true
  }

  private func applyWriteSuccess(
    _ isFavorite: Bool,
    repositoryID: Int,
    version: Int
  ) {
    if isFavorite {
      persistedRepositoryIDs.insert(repositoryID)
    } else {
      persistedRepositoryIDs.remove(repositoryID)
    }

    guard versions[repositoryID] == version else {
      return
    }

    desiredValues[repositoryID] = nil
    pendingRepositoryIDs.remove(repositoryID)
  }

  private func applyWriteFailure(repositoryID: Int, version: Int) {
    guard versions[repositoryID] == version else {
      return
    }

    if persistedRepositoryIDs.contains(repositoryID) {
      favoriteRepositoryIDs.insert(repositoryID)
    } else {
      favoriteRepositoryIDs.remove(repositoryID)
    }

    desiredValues[repositoryID] = nil
    pendingRepositoryIDs.remove(repositoryID)
  }
}
