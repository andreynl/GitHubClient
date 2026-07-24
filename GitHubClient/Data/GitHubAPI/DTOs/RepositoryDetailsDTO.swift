import Foundation

nonisolated struct RepositoryDetailsDTO: Decodable, Sendable {
  let id: Int
  let name: String
  let fullName: String
  let owner: OwnerDTO
  let description: String?
  let stargazersCount: Int
  let forksCount: Int
  let subscribersCount: Int
  let openIssuesCount: Int
  let language: String?
  let defaultBranch: String
  let license: RepositoryLicenseDTO?
  let topics: [String]
  let createdAt: Date?
  let updatedAt: Date?
  let pushedAt: Date?
  let htmlURL: URL?
  let homepage: URL?
  let archived: Bool
  let fork: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case fullName = "full_name"
    case owner
    case description
    case stargazersCount = "stargazers_count"
    case forksCount = "forks_count"
    case subscribersCount = "subscribers_count"
    case openIssuesCount = "open_issues_count"
    case language
    case defaultBranch = "default_branch"
    case license
    case topics
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case pushedAt = "pushed_at"
    case htmlURL = "html_url"
    case homepage
    case archived
    case fork
  }

  func toDomain() -> RepositoryDetails {
    RepositoryDetails(
      id: id,
      name: name,
      fullName: fullName,
      owner: owner.toDomain(),
      description: description,
      starsCount: stargazersCount,
      forksCount: forksCount,
      subscribersCount: subscribersCount,
      openIssuesCount: openIssuesCount,
      language: language,
      defaultBranch: defaultBranch,
      licenseName: license?.name,
      topics: topics,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pushedAt: pushedAt,
      repositoryURL: htmlURL,
      homepageURL: homepage,
      isArchived: archived,
      isFork: fork
    )
  }
}

nonisolated struct RepositoryLicenseDTO: Decodable, Sendable {
  let name: String
}
