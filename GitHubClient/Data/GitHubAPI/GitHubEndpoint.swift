import Foundation

nonisolated struct GitHubEndpoint: Equatable, Sendable {
  let path: String
  let queryItems: [URLQueryItem]

  static func searchRepositories(query: String, page: Int, perPage: Int) -> GitHubEndpoint {
    GitHubEndpoint(
      path: "/search/repositories",
      queryItems: [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "per_page", value: String(perPage)),
      ]
    )
  }

  static func repositoryDetails(owner: String, name: String) -> GitHubEndpoint {
    GitHubEndpoint(
      path: "/repos/\(owner)/\(name)",
      queryItems: []
    )
  }

  func urlRequest(baseURL: URL, accessToken: String?) throws -> URLRequest {
    guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
      throw GitHubAPIError.invalidURL
    }

    components.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components.url else {
      throw GitHubAPIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("GitHubClient", forHTTPHeaderField: "User-Agent")

    if let accessToken, !accessToken.isEmpty {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    return request
  }
}
