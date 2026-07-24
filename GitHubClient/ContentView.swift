import SwiftUI

struct ContentView: View {
  @State private var viewModel: SearchViewModel

  init(container: AppContainer = .live) {
    _viewModel = State(
      initialValue: SearchViewModel(repository: container.repositoriesRepository)
    )
  }

  var body: some View {
    NavigationStack {
      SearchView(viewModel: viewModel)
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
