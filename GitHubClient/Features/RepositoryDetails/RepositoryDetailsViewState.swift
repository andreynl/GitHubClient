enum RepositoryDetailsPhase: Equatable, Sendable {
  case idle
  case loading
  case loaded
  case failed
}

struct RepositoryDetailsViewState: Equatable, Sendable {
  var details: RepositoryDetails?
  var phase: RepositoryDetailsPhase
  var error: AppError?

  static let idle = RepositoryDetailsViewState(
    details: nil,
    phase: .idle,
    error: nil
  )
}
