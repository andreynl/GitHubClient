import SwiftUI

struct SearchHistorySection: View {
  let state: SearchHistoryViewState
  let selectEntry: (SearchHistoryEntry) -> Void
  let clear: () -> Void
  let retry: () -> Void

  var body: some View {
    Section {
      entriesContent
      statusContent
    } header: {
      HStack {
        Text("Recent Searches")
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if !entries.isEmpty {
          Button("Clear", action: clear)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isClearing)
            .accessibilityLabel("Clear all recent searches")
            .accessibilityHint("Deletes all recent searches")
        }
      }
    }
  }

  @ViewBuilder
  private var entriesContent: some View {
    ForEach(entries, id: \.query) { entry in
      Button {
        selectEntry(entry)
      } label: {
        Text(entry.query)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Search for \(entry.query)")
      .accessibilityHint("Starts a repository search")
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    switch state {
    case .loading:
      ProgressView("Loading recent searches")
    case .updating(_, let operation):
      ProgressView(progressLabel(for: operation))
    case .failed(_, let error, _):
      VStack(alignment: .leading, spacing: 8) {
        Text(error.message)
          .font(.footnote)
          .foregroundStyle(.secondary)
        Button("Retry", action: retry)
          .frame(minWidth: 44, minHeight: 44)
      }
    case .idle, .loaded:
      EmptyView()
    }
  }

  private var entries: [SearchHistoryEntry] {
    switch state {
    case .loaded(let entries),
      .updating(let entries, _),
      .failed(let entries, _, _):
      entries
    case .idle, .loading:
      []
    }
  }

  private var isClearing: Bool {
    if case .updating(_, .clear) = state {
      return true
    }
    return false
  }

  private func progressLabel(
    for operation: SearchHistoryOperation
  ) -> LocalizedStringKey {
    switch operation {
    case .load:
      "Loading recent searches"
    case .record:
      "Updating recent searches"
    case .clear:
      "Clearing recent searches"
    }
  }
}
