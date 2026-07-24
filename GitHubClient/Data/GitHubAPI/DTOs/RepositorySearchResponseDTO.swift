nonisolated struct RepositorySearchResponseDTO: Decodable, Sendable {
  let totalCount: Int
  let incompleteResults: Bool
  let items: [RepositoryDTO]

  enum CodingKeys: String, CodingKey {
    case totalCount = "total_count"
    case incompleteResults = "incomplete_results"
    case items
  }

  func toDomain(page: Int, perPage: Int) -> RepositoryPage {
    RepositoryPage(
      items: items.map { $0.toDomain() },
      currentPage: page,
      hasNextPage: page * perPage < totalCount,
      totalCount: totalCount
    )
  }
}
