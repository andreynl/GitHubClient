import Foundation
import Observation

@MainActor
@Observable
final class RepositoryDetailsViewModel {
  private(set) var state = RepositoryDetailsViewState.idle

  let owner: String
  let name: String

  @ObservationIgnored private let repository: RepositoriesRepository
  @ObservationIgnored private var detailsTask: Task<Void, Never>?
  @ObservationIgnored private var readmeTask: Task<Void, Never>?
  @ObservationIgnored private var detailsRequestID = 0
  @ObservationIgnored private var readmeRequestID = 0

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
    detailsTask?.cancel()
    readmeTask?.cancel()
  }

  func load() {
    if state.primary == .idle {
      startDetailsLoading()
    }

    if state.readme == .idle {
      startReadmeLoading()
    }
  }

  func retry() {
    guard case .failed = state.primary else {
      return
    }

    startDetailsLoading()
  }

  func cancel() {
    detailsTask?.cancel()
    detailsTask = nil
    detailsRequestID += 1

    readmeTask?.cancel()
    readmeTask = nil
    readmeRequestID += 1

    if state.primary == .loading {
      state.primary = .idle
    }

    if state.readme == .loading {
      state.readme = .idle
    }
  }

  private func startDetailsLoading() {
    detailsTask?.cancel()
    detailsRequestID += 1
    let activeRequestID = detailsRequestID

    state.primary = .loading

    detailsTask = Task { [weak self, repository, owner, name] in
      do {
        let details = try await repository.repositoryDetails(owner: owner, name: name)
        self?.applyDetails(details, requestID: activeRequestID)
      } catch {
        self?.applyDetailsError(error, requestID: activeRequestID)
      }
    }
  }

  private func startReadmeLoading() {
    guard state.readme == .idle else {
      return
    }

    readmeTask?.cancel()
    readmeRequestID += 1
    let activeRequestID = readmeRequestID
    state.readme = .loading

    readmeTask = Task { [weak self, repository, owner, name] in
      do {
        let readme = try await repository.repositoryReadme(owner: owner, name: name)
        self?.applyReadme(readme, requestID: activeRequestID)
      } catch {
        self?.applyReadmeError(error, requestID: activeRequestID)
      }
    }
  }

  private func applyDetails(_ details: RepositoryDetails, requestID: Int) {
    guard shouldApplyDetailsResponse(requestID: requestID) else {
      return
    }

    state.primary = .loaded(details)
    detailsTask = nil
  }

  private func applyDetailsError(_ error: Error, requestID: Int) {
    guard requestID == detailsRequestID else {
      return
    }

    state.primary = isCancellation(error) ? .idle : .failed(mapError(error))
    detailsTask = nil
  }

  private func applyReadme(_ readme: RepositoryReadme, requestID: Int) {
    guard shouldApplyReadmeResponse(requestID: requestID) else {
      return
    }

    state.readme = .loaded(readme)
    readmeTask = nil
  }

  private func applyReadmeError(_ error: Error, requestID: Int) {
    guard requestID == readmeRequestID else {
      return
    }

    state.readme = isCancellation(error) ? .idle : .unavailable
    readmeTask = nil
  }

  private func shouldApplyDetailsResponse(requestID: Int) -> Bool {
    !Task.isCancelled && requestID == detailsRequestID
  }

  private func shouldApplyReadmeResponse(requestID: Int) -> Bool {
    !Task.isCancelled && requestID == readmeRequestID
  }

  private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || error as? AppError == .cancelled
  }

  private func mapError(_ error: Error) -> AppError {
    if let appError = error as? AppError {
      return appError
    }

    return .unknown
  }
}
