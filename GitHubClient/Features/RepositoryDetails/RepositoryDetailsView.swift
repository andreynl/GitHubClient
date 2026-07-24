import Foundation
import SwiftUI

struct RepositoryDetailsView: View {
  @State private var viewModel: RepositoryDetailsViewModel

  init(viewModel: RepositoryDetailsViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    Group {
      switch viewModel.state.primary {
      case .idle:
        EmptyView()
      case .loading:
        ProgressView("Loading repository")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel("Loading repository details")
      case .loaded(let details):
        detailsContent(details)
      case .failed(let error):
        errorContent(error)
      }
    }
    .navigationTitle(navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if case .loaded(let details) = viewModel.state.primary {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            viewModel.toggleFavorite(repositoryID: details.id)
          } label: {
            if viewModel.favoritesAreLoaded {
              Image(
                systemName: viewModel.isFavorite(repositoryID: details.id)
                  ? "star.fill"
                  : "star"
              )
              .accessibilityHidden(true)
            } else {
              ProgressView()
                .accessibilityHidden(true)
            }
          }
          .disabled(!viewModel.favoritesAreLoaded)
          .accessibilityLabel(favoriteAccessibilityLabel(details))
          .accessibilityHint("Updates this repository's favorite status")
          .accessibilityValue(
            viewModel.isUpdatingFavorite(repositoryID: details.id)
              ? "Saving"
              : ""
          )
        }
      }
    }
    .onAppear {
      viewModel.load()
    }
    .onDisappear {
      viewModel.cancel()
    }
    .task {
      await viewModel.loadFavorites()
    }
  }

  private func favoriteAccessibilityLabel(_ details: RepositoryDetails) -> String {
    guard viewModel.favoritesAreLoaded else {
      return "Loading favorite status for \(details.fullName)"
    }

    return viewModel.isFavorite(repositoryID: details.id)
      ? "Remove \(details.fullName) from favorites"
      : "Add \(details.fullName) to favorites"
  }

  private func detailsContent(_ details: RepositoryDetails) -> some View {
    List {
      Section {
        RepositoryHeaderView(details: details)
      }

      Section("Owner") {
        RepositoryOwnerView(owner: details.owner)
      }

      Section("Statistics") {
        RepositoryMetricRow(title: "Stars", value: details.starsCount, systemImage: "star")
        RepositoryMetricRow(title: "Forks", value: details.forksCount, systemImage: "tuningfork")
        RepositoryMetricRow(title: "Subscribers", value: details.subscribersCount, systemImage: "eye")
        RepositoryMetricRow(
          title: "Open issues",
          value: details.openIssuesCount,
          systemImage: "exclamationmark.circle"
        )
      }

      Section("Metadata") {
        detailRow("Default branch", value: details.defaultBranch)

        if let language = details.language {
          detailRow("Language", value: language)
        }

        if let licenseName = details.licenseName {
          detailRow("License", value: licenseName)
        }

        if !details.topics.isEmpty {
          LabeledContent("Topics") {
            Text(details.topics.joined(separator: ", "))
              .multilineTextAlignment(.trailing)
              .foregroundStyle(.secondary)
          }
        }

        if let createdAt = details.createdAt {
          LabeledContent("Created") {
            Text(createdAt, format: .dateTime.day().month(.abbreviated).year())
          }
        }

        if let updatedAt = details.updatedAt {
          LabeledContent("Updated") {
            Text(updatedAt, format: .dateTime.day().month(.abbreviated).year())
          }
        }

        if details.isFork {
          detailRow("Fork", value: "Yes")
        }
      }

      Section("Links") {
        if let homepageURL = validatedExternalURL(details.homepageURL) {
          ExternalLinkRow(
            title: "Open Homepage",
            destination: homepageURL,
            accessibilityHint: "Opens the repository homepage in your default browser"
          )
        }

        if let repositoryURL = gitHubURL(for: details) {
          ExternalLinkRow(
            title: "Open on GitHub",
            destination: repositoryURL,
            accessibilityHint: "Opens the repository on GitHub in your default browser"
          )
        }
      }

      RepositoryReadmeSection(state: viewModel.state.readme)
    }
  }

  private func errorContent(_ error: AppError) -> some View {
    ContentUnavailableView {
      Label("Unable to load repository", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error.message)
    } actions: {
      Button("Retry") {
        viewModel.retry()
      }
    }
  }

  private var navigationTitle: String {
    guard case .loaded(let details) = viewModel.state.primary else {
      return viewModel.name
    }

    return details.name
  }

  private func detailRow(_ title: String, value: String) -> some View {
    LabeledContent(title, value: value)
  }

  private func gitHubURL(for details: RepositoryDetails) -> URL? {
    if let repositoryURL = validatedExternalURL(details.repositoryURL) {
      return repositoryURL
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/\(details.owner.login)/\(details.name)"
    return components.url
  }

  private func validatedExternalURL(_ url: URL?) -> URL? {
    guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      return nil
    }

    return url
  }
}

private struct RepositoryReadmeSection: View {
  let state: RepositoryReadmeViewState

  @ViewBuilder
  var body: some View {
    switch state {
    case .idle, .unavailable:
      EmptyView()
    case .loading:
      Section {
        ProgressView("Loading README")
          .accessibilityLabel("Loading repository README")
      } header: {
        readmeHeader
      }
    case .loaded(let readme):
      Section {
        Text(readme.content)
          .textSelection(.enabled)
      } header: {
        readmeHeader
      }
    }
  }

  private var readmeHeader: some View {
    Text("README")
      .accessibilityAddTraits(.isHeader)
  }
}

private struct RepositoryHeaderView: View {
  let details: RepositoryDetails

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(details.fullName)
        .font(.title2.weight(.semibold))

      if details.isArchived {
        Label("Archived", systemImage: "archivebox")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(.secondary.opacity(0.12), in: Capsule())
      }

      if let description = details.description, !description.isEmpty {
        Text(description)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct RepositoryOwnerView: View {
  let owner: RepositoryOwner

  var body: some View {
    HStack(spacing: 12) {
      AsyncImage(url: owner.avatarURL) { phase in
        switch phase {
        case .empty:
          ProgressView()
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
        case .failure:
          Image(systemName: "person.crop.circle")
            .resizable()
            .foregroundStyle(.secondary)
        @unknown default:
          Image(systemName: "person.crop.circle")
            .resizable()
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 52, height: 52)
      .clipShape(Circle())
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(owner.login)
          .font(.headline)
        Text("Repository owner")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Repository owner \(owner.login)")
  }
}

private struct RepositoryMetricRow: View {
  let title: String
  let value: Int
  let systemImage: String

  var body: some View {
    LabeledContent {
      Text(value, format: .number)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title), \(value.formatted())")
  }
}

private struct ExternalLinkRow: View {
  let title: String
  let destination: URL
  let accessibilityHint: String

  var body: some View {
    Link(destination: destination) {
      HStack {
        Text(title)
        Spacer()
        Image(systemName: "arrow.up.right.square")
          .accessibilityHidden(true)
      }
    }
    .accessibilityLabel(title)
    .accessibilityHint(accessibilityHint)
  }
}
