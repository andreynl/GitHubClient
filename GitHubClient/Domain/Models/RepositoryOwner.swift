import Foundation

nonisolated struct RepositoryOwner: Equatable, Sendable {
  let id: Int
  let login: String
  let avatarURL: URL?
  let profileURL: URL?
}
