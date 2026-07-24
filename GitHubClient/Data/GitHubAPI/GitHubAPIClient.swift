import Foundation

actor GitHubAPIClient {
  private let baseURL: URL
  private let session: URLSession
  private let decoder: JSONDecoder
  private let accessTokenProvider: AccessTokenProvider?

  init(
    baseURL: URL = URL(string: "https://api.github.com") ?? URL(fileURLWithPath: "/"),
    session: URLSession = .shared,
    accessTokenProvider: AccessTokenProvider? = nil
  ) {
    self.baseURL = baseURL
    self.session = session
    self.accessTokenProvider = accessTokenProvider

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
  }

  func send<Response: Decodable & Sendable>(
    _ endpoint: GitHubEndpoint,
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    do {
      let accessToken = try await accessTokenProvider?.accessToken()
      let request = try endpoint.urlRequest(baseURL: baseURL, accessToken: accessToken)
      let (data, response) = try await session.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw GitHubAPIError.unknown("The response was not an HTTP response.")
      }

      try validate(httpResponse)

      do {
        return try decoder.decode(Response.self, from: data)
      } catch {
        throw GitHubAPIError.decoding(error.localizedDescription)
      }
    } catch let error as GitHubAPIError {
      throw error
    } catch let error as URLError where error.code == .cancelled {
      throw GitHubAPIError.cancelled
    } catch let error as URLError
      where error.code == .notConnectedToInternet || error.code == .networkConnectionLost
    {
      throw GitHubAPIError.offline
    } catch {
      throw GitHubAPIError.transport(error.localizedDescription)
    }
  }

  private func validate(_ response: HTTPURLResponse) throws {
    switch response.statusCode {
    case 200..<300:
      return
    case 401:
      throw GitHubAPIError.unauthorized
    case 403 where isRateLimited(response):
      throw GitHubAPIError.rateLimited(rateLimitInfo(from: response))
    case 429:
      throw GitHubAPIError.rateLimited(rateLimitInfo(from: response))
    case 403:
      throw GitHubAPIError.forbidden
    case 404:
      throw GitHubAPIError.notFound
    case 500..<600:
      throw GitHubAPIError.server(statusCode: response.statusCode)
    default:
      throw GitHubAPIError.unexpectedStatusCode(response.statusCode)
    }
  }

  private func isRateLimited(_ response: HTTPURLResponse) -> Bool {
    let remaining = header("x-ratelimit-remaining", in: response).flatMap(Int.init)
    return response.statusCode == 429 || remaining == 0
  }

  private func rateLimitInfo(from response: HTTPURLResponse) -> RateLimitInfo {
    let limit = header("x-ratelimit-limit", in: response).flatMap(Int.init)
    let remaining = header("x-ratelimit-remaining", in: response).flatMap(Int.init)
    let resetAt = header("x-ratelimit-reset", in: response)
      .flatMap(TimeInterval.init)
      .map { Date(timeIntervalSince1970: $0) }

    return RateLimitInfo(limit: limit, remaining: remaining, resetAt: resetAt)
  }

  private func header(_ name: String, in response: HTTPURLResponse) -> String? {
    response.allHeaderFields.first { key, _ in
      String(describing: key).caseInsensitiveCompare(name) == .orderedSame
    }?.value as? String
  }
}
