import Foundation

nonisolated struct RepositoryDTO: Decodable, Sendable {
  let id: Int
  let name: String
  let fullName: String
  let owner: OwnerDTO
  let description: String?
  let stargazersCount: Int
  let forksCount: Int
  let language: String?
  let updatedAt: Date?
  let htmlURL: URL?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case fullName = "full_name"
    case owner
    case description
    case stargazersCount = "stargazers_count"
    case forksCount = "forks_count"
    case language
    case updatedAt = "updated_at"
    case htmlURL = "html_url"
  }

  func toDomain() -> RepositorySummary {
    RepositorySummary(
      id: id,
      name: name,
      fullName: fullName,
      owner: owner.toDomain(),
      description: description,
      starsCount: stargazersCount,
      forksCount: forksCount,
      language: language,
      updatedAt: updatedAt,
      repositoryURL: htmlURL
    )
  }
}
