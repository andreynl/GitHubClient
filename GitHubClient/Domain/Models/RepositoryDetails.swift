import Foundation

nonisolated struct RepositoryDetails: Equatable, Sendable {
  let id: Int
  let name: String
  let fullName: String
  let owner: RepositoryOwner
  let description: String?
  let starsCount: Int
  let forksCount: Int
  let subscribersCount: Int
  let openIssuesCount: Int
  let language: String?
  let defaultBranch: String
  let licenseName: String?
  let topics: [String]
  let createdAt: Date?
  let updatedAt: Date?
  let pushedAt: Date?
  let repositoryURL: URL?
  let homepageURL: URL?
  let isArchived: Bool
  let isFork: Bool
}
