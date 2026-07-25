import Foundation

nonisolated protocol CacheClock: Sendable {
  func now() -> TimeInterval
}

nonisolated struct SystemCacheClock: CacheClock {
  func now() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
  }
}

nonisolated struct MemoryCachePolicy: Equatable, Sendable {
  static let search = MemoryCachePolicy(
    timeToLive: 5 * 60,
    maximumEntryCount: 100
  )
  static let details = MemoryCachePolicy(
    timeToLive: 5 * 60,
    maximumEntryCount: 50
  )

  let timeToLive: TimeInterval
  let maximumEntryCount: Int

  init(timeToLive: TimeInterval, maximumEntryCount: Int) {
    self.timeToLive = max(0, timeToLive)
    self.maximumEntryCount = max(1, maximumEntryCount)
  }
}
