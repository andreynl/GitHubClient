import Foundation

nonisolated struct RepositorySummary: Identifiable, Equatable, Sendable {
  let id: Int
  let name: String
  let fullName: String
  let owner: RepositoryOwner
  let description: String?
  let starsCount: Int
  let forksCount: Int
  let language: String?
  let updatedAt: Date?
  let repositoryURL: URL?
}
