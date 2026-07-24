nonisolated enum GitHubAPIError: Error, Equatable, Sendable {
  case invalidURL
  case transport(String)
  case decoding(String)
  case unauthorized
  case forbidden
  case rateLimited(RateLimitInfo?)
  case notFound
  case server(statusCode: Int)
  case unexpectedStatusCode(Int)
  case offline
  case cancelled
  case unknown(String)

  var appError: AppError {
    switch self {
    case .invalidURL:
      .invalidURL
    case .transport(let message):
      .transport(message)
    case .decoding(let message):
      .decoding(message)
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
    case .unknown(let message):
      .unknown(message)
    }
  }
}
