import Foundation
import Observation

@MainActor
@Observable
final class RepositoryDetailsViewModel {
  private(set) var state = RepositoryDetailsViewState.idle

  let owner: String
  let name: String

  @ObservationIgnored private let repository: RepositoriesRepository
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var requestID = 0

  init(
    owner: String,
    name: String,
    repository: RepositoriesRepository
  ) {
    self.owner = owner
    self.name = name
    self.repository = repository
  }

  deinit {
    loadTask?.cancel()
  }

  func load() {
    guard state.phase == .idle else {
      return
    }

    startLoading()
  }

  func retry() {
    guard state.phase == .failed else {
      return
    }

    startLoading()
  }

  func cancel() {
    loadTask?.cancel()
    loadTask = nil
    requestID += 1

    if state.phase == .loading {
      state = .idle
    }
  }

  private func startLoading() {
    loadTask?.cancel()
    requestID += 1
    let activeRequestID = requestID

    state.phase = .loading
    state.error = nil

    loadTask = Task { [weak self, repository, owner, name] in
      do {
        let details = try await repository.repositoryDetails(owner: owner, name: name)
        self?.apply(details, requestID: activeRequestID)
      } catch {
        self?.apply(error, requestID: activeRequestID)
      }
    }
  }

  private func apply(_ details: RepositoryDetails, requestID: Int) {
    guard shouldApplyResponse(requestID: requestID) else {
      return
    }

    state.details = details
    state.phase = .loaded
    state.error = nil
    loadTask = nil
  }

  private func apply(_ error: Error, requestID: Int) {
    guard !isCancellation(error), shouldApplyResponse(requestID: requestID) else {
      return
    }

    state.details = nil
    state.phase = .failed
    state.error = mapError(error)
    loadTask = nil
  }

  private func shouldApplyResponse(requestID: Int) -> Bool {
    !Task.isCancelled && requestID == self.requestID
  }

  private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || error as? AppError == .cancelled || error as? GitHubAPIError == .cancelled
  }

  private func mapError(_ error: Error) -> AppError {
    if let appError = error as? AppError {
      return appError
    }

    if let apiError = error as? GitHubAPIError {
      return apiError.appError
    }

    return .unknown(error.localizedDescription)
  }
}
