nonisolated protocol AccessTokenProvider: Sendable {
  func accessToken() async throws -> String?
}
