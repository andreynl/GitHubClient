import SwiftUI

struct FavoritesView: View {
  @Bindable var viewModel: FavoritesViewModel

  var body: some View {
    List {
      content
    }
    .navigationTitle("Favorites")
    .task {
      await viewModel.loadFavorites()
    }
    .task(id: synchronizationID) {
      viewModel.synchronize()
    }
    .refreshable {
      await viewModel.refresh()
    }
    .onDisappear {
      viewModel.cancel()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state {
    case .initializing:
      ProgressView("Loading favorites")
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading favorite repositories")
    case .idle:
      EmptyView()
    case .loading:
      ProgressView("Loading repositories")
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading favorite repositories")
    case .empty:
      ContentUnavailableView(
        "No Favorites Yet",
        systemImage: "star",
        description: Text(
          "Save repositories from Search or Repository Details and they’ll appear here."
        )
      )
    case .failed(let error):
      failureContent(error)
    case .loaded(_, let failedCount, let isRefreshing):
      if failedCount > 0 {
        partialFailureContent(
          failedCount: failedCount,
          isRetrying: isRefreshing
        )
      }

      ForEach(viewModel.visibleRepositories) { repository in
        HStack(spacing: 8) {
          NavigationLink(
            value: AppRoute.repository(
              owner: repository.owner.login,
              name: repository.name
            )
          ) {
            RepositorySummaryRow(repository: repository)
          }
          .accessibilityLabel("Open \(repository.fullName)")

          Button {
            viewModel.toggleFavorite(repositoryID: repository.id)
          } label: {
            Group {
              if viewModel.isUpdating(repositoryID: repository.id) {
                ProgressView()
                  .accessibilityHidden(true)
              } else {
                Image(systemName: "star.fill")
                  .accessibilityHidden(true)
              }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(.yellow)
          .accessibilityLabel("Remove \(repository.fullName) from favorites")
          .accessibilityHint("Removes this repository from Favorites")
          .accessibilityValue(
            viewModel.isUpdating(repositoryID: repository.id) ? "Saving" : ""
          )
        }
      }

      if isRefreshing {
        ProgressView()
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Refreshing favorite repositories")
      }
    }
  }

  private func partialFailureContent(
    failedCount: Int,
    isRetrying: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        failedCount == 1
          ? "One favorite couldn’t be loaded."
          : "\(failedCount) favorites couldn’t be loaded."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      Button("Retry unavailable favorites") {
        viewModel.retry()
      }
      .disabled(isRetrying)
    }
    .accessibilityElement(children: .contain)
  }

  private func failureContent(_ error: AppError) -> some View {
    ContentUnavailableView {
      Label("Unable to load favorites", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error.message)
    } actions: {
      Button("Retry loading favorites") {
        viewModel.retry()
      }
    }
  }

  private var synchronizationID: FavoritesSynchronizationID {
    FavoritesSynchronizationID(
      isLoaded: viewModel.favoritesAreLoaded,
      repositoryIDs: viewModel.favoriteRepositoryIDs.sorted()
    )
  }
}

private struct FavoritesSynchronizationID: Equatable {
  let isLoaded: Bool
  let repositoryIDs: [Int]
}
