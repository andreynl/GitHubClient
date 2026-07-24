import SwiftUI

struct SearchView: View {
  @Bindable var viewModel: SearchViewModel

  var body: some View {
    List {
      content
    }
    .navigationTitle("Repositories")
    .searchable(text: searchText, prompt: "Search GitHub")
    .task {
      await viewModel.loadFavorites()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state.phase {
    case .idle:
      ContentUnavailableView(
        "Search repositories",
        systemImage: "magnifyingglass",
        description: Text("Enter at least \(viewModel.minimumQueryLength) characters.")
      )
    case .initialLoading:
      ProgressView()
        .frame(maxWidth: .infinity)
    case .empty:
      ContentUnavailableView.search(text: viewModel.state.query)
    case .failed:
      errorView(viewModel.state.error)
    case .loaded:
      ForEach(viewModel.state.items) { repository in
        HStack(spacing: 8) {
          NavigationLink(
            value: AppRoute.repository(
              owner: repository.owner.login,
              name: repository.name
            )
          ) {
            RepositorySummaryRow(repository: repository)
          }

          FavoriteButton(
            repositoryName: repository.fullName,
            isLoaded: viewModel.favoritesAreLoaded,
            isFavorite: viewModel.isFavorite(repositoryID: repository.id),
            isUpdating: viewModel.isUpdatingFavorite(repositoryID: repository.id)
          ) {
            viewModel.toggleFavorite(repositoryID: repository.id)
          }
        }
        .onAppear {
          if repository.id == viewModel.state.items.last?.id {
            viewModel.loadNextPage()
          }
        }
      }

      paginationContent
    }
  }

  @ViewBuilder
  private var paginationContent: some View {
    switch viewModel.state.pagination {
    case .idle:
      EmptyView()
    case .loadingNextPage:
      ProgressView()
        .frame(maxWidth: .infinity)
    case .failed(let error):
      VStack(alignment: .leading, spacing: 8) {
        Text(error.message)
          .font(.footnote)
          .foregroundStyle(.secondary)
        Button("Retry") {
          viewModel.retry()
        }
      }
    case .endReached:
      EmptyView()
    }
  }

  private func errorView(_ error: AppError?) -> some View {
    ContentUnavailableView {
      Label("Unable to load repositories", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error?.message ?? "Try again later.")
    } actions: {
      Button("Retry") {
        viewModel.retry()
      }
    }
  }

  private var searchText: Binding<String> {
    Binding(
      get: { viewModel.state.query },
      set: { viewModel.updateQuery($0) }
    )
  }
}

private struct FavoriteButton: View {
  let repositoryName: String
  let isLoaded: Bool
  let isFavorite: Bool
  let isUpdating: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Group {
        if isLoaded {
          Image(systemName: isFavorite ? "star.fill" : "star")
            .accessibilityHidden(true)
        } else {
          ProgressView()
            .accessibilityHidden(true)
        }
      }
      .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.plain)
    .foregroundStyle(isFavorite ? .yellow : .secondary)
    .disabled(!isLoaded)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Updates this repository's favorite status")
    .accessibilityValue(isUpdating ? "Saving" : "")
  }

  private var accessibilityLabel: String {
    guard isLoaded else {
      return "Loading favorite status for \(repositoryName)"
    }

    return isFavorite
      ? "Remove \(repositoryName) from favorites"
      : "Add \(repositoryName) to favorites"
  }
}
