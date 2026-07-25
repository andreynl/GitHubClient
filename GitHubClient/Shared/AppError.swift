import Foundation

nonisolated enum AppError: Error, Equatable, Sendable {
  case invalidURL
  case transport
  case decoding
  case unauthorized
  case forbidden
  case rateLimited(RateLimitInfo?)
  case notFound
  case server(statusCode: Int)
  case unexpectedStatusCode(Int)
  case offline
  case cancelled
  case unknown

  var message: String {
    switch self {
    case .invalidURL:
      "The request URL could not be created."
    case .transport:
      "The request could not be completed. Try again."
    case .decoding:
      "The response could not be read."
    case .unauthorized:
      "GitHub rejected the request."
    case .forbidden:
      "GitHub blocked the request."
    case .rateLimited(let info):
      if let retryAfterSeconds = info?.retryAfterSeconds {
        "GitHub rate limit reached. Try again in \(retryAfterSeconds) seconds."
      } else if let resetAt = info?.resetAt {
        "GitHub rate limit reached. Try again after \(resetAt.formatted(date: .omitted, time: .shortened))."
      } else {
        "GitHub rate limit reached. Try again later."
      }
    case .notFound:
      "The requested resource was not found."
    case .server:
      "GitHub is having trouble. Try again later."
    case .unexpectedStatusCode(let statusCode):
      "Unexpected response: \(statusCode)."
    case .offline:
      "The network appears to be offline."
    case .cancelled:
      "The request was cancelled."
    case .unknown:
      "Something went wrong. Try again."
    }
  }
}
