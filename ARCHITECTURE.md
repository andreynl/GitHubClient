# ARCHITECTURE.md

# GitHubClient Architecture

## Overview

GitHubClient is built using **Clean Architecture** with **MVVM**, **Repository Pattern**, and **Swift Concurrency**.

The architecture emphasizes:

- clear separation of responsibilities
- scalability
- maintainability
- testability
- deterministic asynchronous behavior

The project is organized by features while preserving strict architectural boundaries.

---

# High-Level Architecture

```
                +----------------------+
                |    SwiftUI Views     |
                +----------+-----------+
                           |
                           v
                +----------------------+
                |      ViewModels      |
                +----------+-----------+
                           |
                           v
                +----------------------+
                |        Domain        |
                |  Use Cases / Models  |
                | Repository Protocols |
                +----------+-----------+
                           ^
                           |
                +----------+-----------+
                |         Data         |
                | Repository Impl.     |
                | API Client           |
                | Persistence          |
                +----------------------+
```

Dependencies always point inward.

The Domain layer never depends on Presentation or Data.

---

# Architectural Principles

The project follows these principles:

- Single Responsibility Principle
- Dependency Inversion
- Composition over inheritance
- Explicit state management
- Protocol-oriented design
- Structured concurrency
- Small, focused types

Every layer has one clear responsibility.

---

# Layer Responsibilities

## Presentation

Contains:

- SwiftUI Views
- ViewModels
- Navigation
- UI state

Responsibilities:

- display state
- handle user interaction
- trigger business operations
- react to state changes

Presentation never:

- performs networking
- talks directly to persistence
- owns business logic

---

## Domain

Contains:

- Entities
- Repository protocols
- Business rules

The Domain layer is platform independent.

It knows nothing about:

- SwiftUI
- UIKit
- URLSession
- persistence

---

## Data

Contains:

- API clients
- DTOs
- Repository implementations
- Persistence

Responsibilities:

- network communication
- JSON decoding
- mapping DTOs to domain models
- storing local data

DTOs never leave this layer.

---

# Feature Structure

Each feature is self-contained.

Example:

```
Search/

    Views/

    ViewModels/

    Models/

    Components/
```

Feature-specific code remains inside its feature.

Shared code belongs in the Shared module.

---

# State Management

User-visible states are represented explicitly.

Typical states include:

- loading
- loaded
- empty
- refreshing
- partial failure
- failure

Avoid managing complex UI using multiple unrelated Boolean flags.

Prefer expressive enums whenever possible.

---

# Repository Pattern

ViewModels communicate only through repository protocols.

Example:

```
ViewModel
      |
      v
Repository Protocol
      ^
      |
Repository Implementation
      |
      v
API / Persistence
```

This provides:

- loose coupling
- easy testing
- dependency inversion

---

# Dependency Injection

Dependencies are injected from the composition root.

Never instantiate repositories inside ViewModels.

Never instantiate API clients inside Views.

Benefits:

- testability
- flexibility
- replaceable implementations

---

# Swift Concurrency

The project uses structured concurrency.

Preferred tools:

- async/await
- Task
- TaskGroup

Avoid:

- Task.detached
- blocking synchronization
- semaphores

UI updates occur on MainActor.

Long-running work should support cancellation.

Stale asynchronous responses must never overwrite newer state.

---

# Favorites Synchronization

FavoritesStore is the single source of truth.

Repository identifiers are persisted.

Search, Details, and Favorites remain synchronized through the shared store.

The application avoids duplicate ownership of favorite state.

---

# Error Handling

Errors are mapped into domain-friendly representations.

Views display user-friendly messages.

Transport details remain inside the Data layer.

Refresh failures should preserve existing content whenever possible.

---

# Testing Strategy

Architecture is designed for deterministic testing.

Key principles:

- protocol abstractions
- fake repositories
- dependency injection
- isolated ViewModels
- predictable async behavior

The architecture intentionally avoids hidden dependencies.

---

# Folder Organization

```
GitHubClient

├── App
├── Features
├── Domain
├── Data
├── Shared
└── Resources
```

Each folder has a single responsibility.

---

# Adding a New Feature

When adding a feature:

1. Define domain models if needed.
2. Extend repository protocols.
3. Implement the repository.
4. Create the ViewModel.
5. Build SwiftUI views.
6. Add tests.
7. Review architecture.
8. Review tests.
9. Merge.

---

# Design Goals

The architecture prioritizes:

- readability
- scalability
- maintainability
- testability
- explicit dependencies
- deterministic concurrency

The goal is not the smallest amount of code, but the clearest and safest design.
