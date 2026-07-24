struct AppContainer {
  let repositoriesRepository: RepositoriesRepository

  static let live = AppContainer(
    repositoriesRepository: GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient()
    )
  )
}
