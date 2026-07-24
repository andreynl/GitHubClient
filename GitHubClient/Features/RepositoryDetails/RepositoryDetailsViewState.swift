enum RepositoryDetailsPhase: Equatable, Sendable {
  case idle
  case loading
  case loaded
  case failed
}

enum RepositoryReadmeViewState: Equatable, Sendable {
  case idle
  case loading
  case loaded(RepositoryReadme)
  case unavailable
}

struct RepositoryDetailsViewState: Equatable, Sendable {
  var details: RepositoryDetails?
  var phase: RepositoryDetailsPhase
  var error: AppError?
  var readme: RepositoryReadmeViewState

  static let idle = RepositoryDetailsViewState(
    details: nil,
    phase: .idle,
    error: nil,
    readme: .idle
  )
}
