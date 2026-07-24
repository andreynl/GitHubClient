import Foundation

nonisolated struct OwnerDTO: Decodable, Sendable {
  let id: Int
  let login: String
  let avatarURL: URL?
  let htmlURL: URL?

  enum CodingKeys: String, CodingKey {
    case id
    case login
    case avatarURL = "avatar_url"
    case htmlURL = "html_url"
  }

  func toDomain() -> RepositoryOwner {
    RepositoryOwner(
      id: id,
      login: login,
      avatarURL: avatarURL,
      profileURL: htmlURL
    )
  }
}
