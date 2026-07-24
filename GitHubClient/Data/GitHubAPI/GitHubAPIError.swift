import Foundation

nonisolated struct GitHubErrorDiagnostics: Equatable, Sendable {
  let domain: String
  let code: Int
  let debugDescription: String

  init(error: Error) {
    let error = error as NSError
    domain = error.domain
    code = error.code
    debugDescription = error.debugDescription
  }

  init(domain: String, code: Int, debugDescription: String) {
    self.domain = domain
    self.code = code
    self.debugDescription = debugDescription
  }
}

nonisolated enum GitHubAPIError: Error, Equatable, Sendable {
  case invalidURL
  case transport(GitHubErrorDiagnostics)
  case decoding(GitHubErrorDiagnostics)
  case unauthorized
  case forbidden
  case rateLimited(RateLimitInfo?)
  case notFound
  case server(statusCode: Int)
  case unexpectedStatusCode(Int)
  case offline
  case cancelled
  case unknown(GitHubErrorDiagnostics)

  var appError: AppError {
    switch self {
    case .invalidURL:
      .invalidURL
    case .transport:
      .transport
    case .decoding:
      .decoding
    case .unauthorized:
      .unauthorized
    case .forbidden:
      .forbidden
    case .rateLimited(let info):
      .rateLimited(info)
    case .notFound:
      .notFound
    case .server(let statusCode):
      .server(statusCode: statusCode)
    case .unexpectedStatusCode(let statusCode):
      .unexpectedStatusCode(statusCode)
    case .offline:
      .offline
    case .cancelled:
      .cancelled
    case .unknown:
      .unknown
    }
  }
}
