# AGENTS.md

# AI Development Guidelines

This document defines the engineering rules for all AI agents working on this repository.

These instructions apply to every implementation, review, refactoring, and test change unless explicitly overridden by the project owner.

---

# Project Overview

GitHubClient is a production-inspired iOS application demonstrating modern iOS engineering practices.

Primary goals:

- Clean Architecture
- MVVM
- SwiftUI
- Swift Concurrency
- Deterministic testing
- Production-quality code
- Maintainable architecture

---

# Architecture

The application follows Clean Architecture.

```
Presentation
      │
      ▼
    Domain
      ▲
      │
      ▼
     Data
```

## Dependency Rules

Presentation depends on Domain abstractions and the application-wide
`AppError` contract in `Shared`.

Data depends on Domain abstractions and converts infrastructure failures into
the same `AppError` contract.

Domain depends on nothing.

`AppError` is a deliberate cross-layer contract in this single-target project,
not a compiler-enforced module boundary. Reconsider its placement if the
project is modularized.

---

# Presentation Layer

Views should:

- render state
- forward user actions
- contain no business logic
- contain no networking
- contain no persistence logic

ViewModels should:

- own UI state
- coordinate async work
- depend only on abstractions
- never import UIKit

---

# Domain Layer

Domain contains:

- models
- repository protocols
- business rules

Domain must never depend on:

- SwiftUI
- UIKit
- networking
- persistence

---

# Data Layer

Data contains:

- API clients
- repository implementations
- DTO mapping
- persistence

DTOs never leave the data layer.

---

# Dependency Injection

Always inject dependencies.

Never instantiate repositories inside ViewModels.

Never create API clients inside Views.

Composition root owns dependency creation.

---

# Swift Concurrency

Always prefer structured concurrency.

Use:

- async/await
- Task
- TaskGroup

Avoid:

- Task.detached
- semaphores
- blocking waits

UI updates belong on MainActor.

Protect against stale asynchronous responses.

Cancellation should be explicit.

---

# State Management

Represent meaningful UI states explicitly.

Prefer enums over multiple booleans.

Example:

- loading
- loaded
- empty
- partialFailure
- failure

Preserve existing content during refresh failures whenever possible.

---

# Favorites

FavoritesStore is the single source of truth.

Persist repository identifiers.

Do not persist complete repository models.

Search, Details and Favorites must stay synchronized.

---

# Error Handling

Map transport errors into application errors.

Views should never display raw networking errors.

User-facing messages should be understandable.

---

# Accessibility

Interactive controls should remain accessible.

Support:

- Dynamic Type
- VoiceOver
- minimum tap targets

Avoid relying on color alone.

---

# Testing

Every feature requires tests.

Tests must be deterministic.

Prefer controlled fakes.

Do not use Task.sleep to define correctness.

Test:

- success
- failure
- empty states
- retry
- refresh
- cancellation
- stale responses
- race conditions
- cleanup

Outstanding asynchronous work should always return to zero.

Regression tests must never be removed without approval.

Production code must not include test-only hooks.

---

# Scope Control

Implement only the approved phase.

Never expand scope.

Never implement future roadmap items.

Never perform unrelated refactoring.

Avoid cosmetic cleanup unless requested.

---

# Review Workflow

Every feature follows this workflow.

```
Planning

↓

Implementation

↓

Architecture Review

↓

Architecture Approved

↓

Test Review

↓

Tests Approved

↓

Merge Review

↓

Commit
```

Once Architecture Review is approved, architecture should not be reopened unless a correctness issue is discovered.

Once Test Review is approved, testing should not expand beyond verified defects.

---

# Validation

Before reporting completion:

- project builds successfully
- all tests pass
- no compiler warnings
- no analyzer warnings
- git diff --check passes
- git status is clean

Always report validation results.

---

# Git Rules

Never:

- commit automatically
- push automatically
- amend commits
- create tags
- modify AGENTS.md

unless explicitly instructed.

---

# Reporting

Implementation reports should include:

1. Summary
2. Architecture impact
3. Files changed
4. Behavior implemented
5. Tests added
6. Validation results
7. Git status

---

# Code Style

Prefer:

- small ViewModels
- explicit state
- composition
- protocol abstractions
- readable naming
- feature-based organization

Avoid:

- force unwraps
- large files
- duplicated logic
- hidden side effects
- unnecessary abstractions

---

# AI Behavior

When unsure:

Ask instead of guessing.

Do not invent requirements.

Do not silently expand scope.

Prefer existing components.

Minimize the size of changes.

Explain trade-offs when multiple reasonable solutions exist.

Respect previous architectural decisions unless explicitly asked to revisit them.

The goal is long-term maintainability, not the shortest implementation.

# Phase Workflow

Every new phase starts with:

1. Planning
2. Scope approval

Only after approval:

3. Implementation

Then:

4. Architecture Review
5. Test Review
6. Merge Review
7. Commit

A review must improve correctness but must not expand the approved scope.
