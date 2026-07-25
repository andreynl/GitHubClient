import SwiftUI

struct ContentView: View {
  @State private var searchViewModel: SearchViewModel
  @State private var favoritesViewModel: FavoritesViewModel
  private let repositoriesRepository: RepositoriesRepository
  private let favoritesStore: FavoritesStore

  init(container: AppContainer = .live) {
    repositoriesRepository = container.repositoriesRepository
    favoritesStore = container.favoritesStore
    _searchViewModel = State(
      initialValue: SearchViewModel(
        repository: container.repositoriesRepository,
        favoritesStore: container.favoritesStore
      )
    )
    _favoritesViewModel = State(
      initialValue: FavoritesViewModel(
        repository: container.repositoriesRepository,
        favoritesStore: container.favoritesStore
      )
    )
  }

  var body: some View {
    TabView {
      NavigationStack {
        SearchView(viewModel: searchViewModel)
          .navigationDestination(for: AppRoute.self) { route in
            repositoryDestination(route)
          }
      }
      .tabItem {
        Label("Search", systemImage: "magnifyingglass")
      }

      NavigationStack {
        FavoritesView(viewModel: favoritesViewModel)
          .navigationDestination(for: AppRoute.self) { route in
            repositoryDestination(route)
        }
      }
      .tabItem {
        Label("Favorites", systemImage: "star")
      }
    }
  }

  private func repositoryDestination(_ route: AppRoute) -> some View {
    switch route {
    case .repository(let owner, let name):
      RepositoryDetailsView(
        viewModel: RepositoryDetailsViewModel(
          owner: owner,
          name: name,
          repository: repositoriesRepository,
          favoritesStore: favoritesStore
        )
      )
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView(container: PreviewFactory.container())
  }
}
