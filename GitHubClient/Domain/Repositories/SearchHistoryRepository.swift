nonisolated protocol SearchHistoryRepository: Sendable {
  func loadHistory() async throws -> [SearchHistoryEntry]
  func recordSuccessfulQuery(_ query: String) async throws
    -> [SearchHistoryEntry]
  func clearHistory() async throws
}
