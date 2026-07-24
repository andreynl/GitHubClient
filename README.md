# GitHubClient

> A production-inspired iOS application built with **SwiftUI**, **Clean Architecture**, **MVVM**, and **Swift Concurrency**.

GitHubClient demonstrates how to build a scalable iOS application with a strong focus on architecture, testability, concurrency, and maintainability.

The project was developed incrementally using a phase-based workflow, where each feature is designed, implemented, reviewed, tested, and documented before moving to the next milestone.

---

## Features

### Search Repositories

- Search public GitHub repositories
- Debounced search
- Loading, empty and error states
- Pagination support

### Repository Details

- Repository information
- Owner information
- Favorite support

### Favorites

- Persistent favorites
- Shared synchronization between screens
- Refresh support
- Partial failure handling
- Optimistic UI updates with rollback

---

## Architecture

The application follows **Clean Architecture**.

```text
                Presentation
          SwiftUI + ViewModels
                    │
                    ▼
                 Domain
     Models + Repository Protocols
                    ▲
                    │
                    ▼
                   Data
    API Clients + Repository Implementations
```

Main architectural principles:

- Clean Architecture
- MVVM
- Repository Pattern
- Dependency Injection
- Swift Structured Concurrency
- Explicit State Management
- Protocol-oriented design

---

## Tech Stack

### Language

- Swift 6

### UI

- SwiftUI

### Architecture

- Clean Architecture
- MVVM
- Repository Pattern

### Concurrency

- async/await
- Task
- TaskGroup
- MainActor

### Testing

- XCTest
- Controlled Fakes
- Deterministic Concurrency Tests

### Networking

- URLSession
- GitHub REST API

---

## Project Structure

```text
GitHubClient
│
├── App
├── Features
│   ├── Search
│   ├── RepositoryDetails
│   └── Favorites
│
├── Domain
│
├── Data
│
├── Shared
│
└── Resources
```

---

## Development Workflow

Every feature follows the same workflow.

```text
Planning
      ↓
Implementation
      ↓
Architecture Review
      ↓
Test Review
      ↓
Merge Review
      ↓
Commit
```

This helps keep every feature small, well-tested and maintainable.

---

## Testing

The project focuses heavily on deterministic testing.

Highlights include:

- Controlled fake repositories
- Cancellation testing
- Stale response protection
- Race condition testing
- Async workflow validation
- Edge case coverage

Timing-based tests are avoided whenever possible.

---

## Quality Goals

The project aims to demonstrate:

- scalable architecture
- maintainable code
- explicit state management
- safe concurrency
- deterministic testing
- production-ready design

---

## Roadmap

| Phase | Status |
|--------|--------|
| Phase 1 | ✅ |
| Phase 2 | ✅ |
| Phase 3 | ✅ |
| Phase 4 | ✅ |
| Phase 5 | ✅ |
| Phase 6 | ⬜ Planned |

Detailed roadmap:

- 📄 ROADMAP.md

---

## Documentation

Additional documentation can be found in:

- 📄 AGENTS.md
- 📄 ARCHITECTURE.md
- 📄 ROADMAP.md
- 📄 CONTRIBUTING.md

---

## Build

```bash
git clone https://github.com/<your-account>/GitHubClient.git

cd GitHubClient

open GitHubClient.xcodeproj
```

Build using Xcode or

```bash
xcodebuild \
-project GitHubClient.xcodeproj \
-scheme GitHubClient \
-destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Running Tests

```bash
xcodebuild test \
-project GitHubClient.xcodeproj \
-scheme GitHubClient \
-destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Why This Project?

This project was created as a portfolio application to demonstrate professional iOS development practices rather than simply implementing features.

The primary goals are:

- clean architecture
- testability
- concurrency correctness
- maintainability
- production-quality engineering practices

---

## License

MIT
