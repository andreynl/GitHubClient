enum RepositoryDetailsPrimaryState: Equatable, Sendable {
  case idle
  case loading
  case loaded(RepositoryDetails)
  case failed(AppError)
}

enum RepositoryReadmeViewState: Equatable, Sendable {
  case idle
  case loading
  case loaded(RepositoryReadme)
  case unavailable
}

struct RepositoryDetailsViewState: Equatable, Sendable {
  var primary: RepositoryDetailsPrimaryState
  var readme: RepositoryReadmeViewState

  static let idle = RepositoryDetailsViewState(
    primary: .idle,
    readme: .idle
  )
}
