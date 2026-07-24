# CONTRIBUTING.md

# Contributing

Thank you for contributing to GitHubClient.

This document describes the project's engineering workflow and quality expectations.

---

# Philosophy

The project prioritizes:

- correctness
- readability
- maintainability
- deterministic behavior
- long-term quality

Feature completeness is never more important than code quality.

---

# Development Workflow

Every contribution follows the same workflow.

```
Planning

↓

Scope Approval

↓

Implementation

↓

Architecture Review

↓

Architecture Approved

↓

Test Review

↓

Merge Review

↓

Commit
```

---

# Scope

Each pull request should implement exactly one approved scope.

Avoid:

- unrelated refactoring
- formatting-only commits
- architectural rewrites
- feature expansion

Small changes are preferred over large changes.

---

# Code Style

Prefer:

- small types
- descriptive names
- protocol abstractions
- composition
- explicit state

Avoid:

- force unwraps
- duplicated code
- hidden side effects
- unnecessary abstractions

---

# Architecture

Follow:

- Clean Architecture
- MVVM
- Repository Pattern
- Dependency Injection

Do not introduce dependencies that violate architectural boundaries.

---

# Concurrency

Prefer:

- async/await
- Task
- TaskGroup

Avoid:

- Task.detached
- blocking synchronization
- shared mutable state

Support cancellation whenever appropriate.

Protect against stale asynchronous updates.

---

# Testing

Every new feature should include tests.

Test:

- success
- failure
- empty states
- cancellation
- retry
- refresh
- edge cases

Tests should be deterministic.

Avoid timing-dependent assertions.

---

# Reviews

Every change should be reviewed for:

## Architecture

- dependency direction
- separation of concerns
- maintainability

## Testing

- correctness
- edge cases
- determinism

## Code Quality

- readability
- simplicity
- consistency

---

# Git

Do not:

- rewrite history
- amend commits
- force push

unless explicitly requested.

Keep commits focused and descriptive.

---

# Documentation

Update documentation whenever architecture or behavior changes.

Keep:

- README.md
- AGENTS.md
- ARCHITECTURE.md
- ROADMAP.md
- CONTRIBUTING.md

consistent with the implementation.

---

# Goal

The goal of every contribution is to leave the project in a better state than before without increasing unnecessary complexity.
