struct AppContainer {
  let repositoriesRepository: RepositoriesRepository
  let favoritesStore: FavoritesStore

  static let live = AppContainer(
    repositoriesRepository: GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient()
    ),
    favoritesStore: FavoritesStore(
      repository: UserDefaultsFavoritesRepository()
    )
  )
}
