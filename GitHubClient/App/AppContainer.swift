struct AppContainer {
  let repositoriesRepository: RepositoriesRepository
  let favoritesStore: FavoritesStore
  let searchHistoryRepository: any SearchHistoryRepository

  static let live = AppContainer(
    repositoriesRepository: GitHubRepositoriesRepository(
      apiClient: GitHubAPIClient()
    ),
    favoritesStore: FavoritesStore(
      repository: UserDefaultsFavoritesRepository()
    ),
    searchHistoryRepository: UserDefaultsSearchHistoryRepository(
      key: "com.andreynl.GitHubClient.searchHistory",
      maximumCapacity: 10
    )
  )
}
