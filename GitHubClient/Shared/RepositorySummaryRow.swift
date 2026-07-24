import SwiftUI

struct RepositorySummaryRow: View {
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
    .accessibilityElement(children: .combine)
  }
}
