# GitHubClient

GitHubClient is an iOS 26+ portfolio application for searching public GitHub
repositories, viewing repository details and README content, and maintaining a
persisted list of favorites.

## Features

- Debounced repository search with pagination, retry, cancellation, and
  process-local caching
- Typed navigation to repository details
- Repository metadata, owner avatar, statistics, topics, dates, and external
  links
- Raw-text README loading that fails independently from repository details
- Persistent favorite repository IDs backed by `UserDefaults`
- Shared favorite state across Search, Repository Details, and Favorites
- Favorites refresh, bounded concurrent loading, partial-failure handling, and
  optimistic removal with rollback

## Implementation

- Swift 6 language mode
- SwiftUI and the Observation framework
- MVVM with folder-level Presentation, Domain, and Data boundaries
- Repository protocols and constructor-based dependency injection
- `async`/`await`, owned tasks, task groups, actors, cancellation, and
  stale-response protection
- URLSession and the GitHub REST API
- Swift Testing with controlled fakes and isolated persistence tests

The live configuration uses GitHub's unauthenticated public API. An access-token
provider can be injected into the API client, but the application does not ship
with credentials.

## Project Structure

```text
GitHubClient/
├── App/                    Composition and typed routes
├── Assets.xcassets/
├── Data/
│   ├── Cache/
│   ├── GitHubAPI/
│   ├── Persistence/
│   └── Repositories/
├── Domain/
│   ├── Models/
│   └── Repositories/
├── Features/
│   ├── Favorites/
│   ├── FavoritesList/
│   ├── RepositoryDetails/
│   └── Search/
└── Shared/

GitHubClientTests/
```

The layers are folders in one application target, not separate Swift modules.
See [ARCHITECTURE.md](ARCHITECTURE.md) and the accepted decisions under
[docs/adr](docs/adr/).

## Requirements

Validation for this revision uses Xcode 26.6 and an installed iOS Simulator
runtime. The current project deployment target is iOS 26.0.

## Build

```bash
git clone https://github.com/andreynl/GitHubClient.git
cd GitHubClient

xcodebuild \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To choose a simulator for tests:

```bash
xcrun simctl list devices available
```

Then use an available device identifier:

```bash
xcodebuild \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Documentation

- [AGENTS.md](AGENTS.md) — AI development guidelines
- [ARCHITECTURE.md](ARCHITECTURE.md) — implemented architecture
- [ROADMAP.md](ROADMAP.md) — completed phase history and planned work
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution workflow
- [docs/adr](docs/adr/) — accepted architecture decisions

## License

GitHubClient is available under the [MIT License](LICENSE).
