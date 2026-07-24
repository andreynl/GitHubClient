import SwiftUI

struct ContentView: View {
  @State private var viewModel: SearchViewModel
  private let repositoriesRepository: RepositoriesRepository

  init(container: AppContainer = .live) {
    repositoriesRepository = container.repositoriesRepository
    _viewModel = State(
      initialValue: SearchViewModel(
        repository: container.repositoriesRepository,
        favoritesStore: container.favoritesStore
      )
    )
  }

  var body: some View {
    NavigationStack {
      SearchView(viewModel: viewModel)
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case .repository(let owner, let name):
            RepositoryDetailsView(
              viewModel: RepositoryDetailsViewModel(
                owner: owner,
                name: name,
                repository: repositoriesRepository,
                favoritesStore: viewModel.favoritesStore
              )
            )
          }
        }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
