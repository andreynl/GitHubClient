import SwiftUI

struct SearchView: View {
  @Bindable var viewModel: SearchViewModel

  var body: some View {
    List {
      content
    }
    .navigationTitle("Repositories")
    .searchable(text: searchText, prompt: "Search GitHub")
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
        NavigationLink(
          value: AppRoute.repository(
            owner: repository.owner.login,
            name: repository.name
          )
        ) {
          RepositorySummaryRow(repository: repository)
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

private struct RepositorySummaryRow: View {
  let repository: RepositorySummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(repository.fullName)
          .font(.headline)
        Spacer()
        Label("\(repository.starsCount)", systemImage: "star")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let description = repository.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }

      HStack(spacing: 12) {
        if let language = repository.language {
          Text(language)
        }

        Label("\(repository.forksCount)", systemImage: "tuningfork")

        if let updatedAt = repository.updatedAt {
          Text(updatedAt, style: .date)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }
}
