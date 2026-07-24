import Foundation

nonisolated struct RateLimitInfo: Equatable, Sendable {
  let limit: Int?
  let remaining: Int?
  let resetAt: Date?
}
