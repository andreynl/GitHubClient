import SwiftUI

struct RepositoryDetailsView: View {
  @State private var viewModel: RepositoryDetailsViewModel

  init(viewModel: RepositoryDetailsViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    Group {
      switch viewModel.state.phase {
      case .idle, .loading:
        ProgressView("Loading repository")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel("Loading repository details")
      case .loaded:
        if let details = viewModel.state.details {
          detailsContent(details)
        }
      case .failed:
        errorContent
      }
    }
    .navigationTitle(viewModel.state.details?.name ?? viewModel.name)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.load()
    }
    .onDisappear {
      viewModel.cancel()
    }
  }

  private func detailsContent(_ details: RepositoryDetails) -> some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(details.fullName)
            .font(.title2.weight(.semibold))

          if let description = details.description, !description.isEmpty {
            Text(description)
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
      }

      Section("Repository") {
        detailRow("Owner", value: details.owner.login)
        detailRow("Default branch", value: details.defaultBranch)

        if let language = details.language {
          detailRow("Language", value: language)
        }

        if let licenseName = details.licenseName {
          detailRow("License", value: licenseName)
        }
      }

      Section("Activity") {
        metricRow("Stars", value: details.starsCount, systemImage: "star")
        metricRow("Forks", value: details.forksCount, systemImage: "tuningfork")
        metricRow("Subscribers", value: details.subscribersCount, systemImage: "eye")
        metricRow("Open issues", value: details.openIssuesCount, systemImage: "exclamationmark.circle")
      }

      if !details.topics.isEmpty {
        Section("Topics") {
          Text(details.topics.joined(separator: ", "))
            .foregroundStyle(.secondary)
        }
      }

      Section("Status") {
        detailRow("Archived", value: details.isArchived ? "Yes" : "No")
        detailRow("Fork", value: details.isFork ? "Yes" : "No")

        if let updatedAt = details.updatedAt {
          LabeledContent("Updated") {
            Text(updatedAt, style: .date)
          }
        }
      }
    }
  }

  private var errorContent: some View {
    ContentUnavailableView {
      Label("Unable to load repository", systemImage: "exclamationmark.triangle")
    } description: {
      Text(viewModel.state.error?.message ?? "Try again later.")
    } actions: {
      Button("Retry") {
        viewModel.retry()
      }
    }
  }

  private func detailRow(_ title: String, value: String) -> some View {
    LabeledContent(title, value: value)
  }

  private func metricRow(_ title: String, value: Int, systemImage: String) -> some View {
    LabeledContent {
      Text(value, format: .number)
    } label: {
      Label(title, systemImage: systemImage)
    }
  }
}
