import Foundation

nonisolated struct RateLimitInfo: Equatable, Sendable {
  let limit: Int?
  let remaining: Int?
  let resetAt: Date?
  let retryAfterSeconds: Int?

  init(
    limit: Int?,
    remaining: Int?,
    resetAt: Date?,
    retryAfterSeconds: Int? = nil
  ) {
    self.limit = limit
    self.remaining = remaining
    self.resetAt = resetAt
    self.retryAfterSeconds = retryAfterSeconds
  }
}
