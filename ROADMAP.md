# ROADMAP.md

# GitHubClient Roadmap

This document tracks the evolution of the project.

The goal is continuous improvement while maintaining high engineering quality.

---

# Guiding Principles

Every phase should:

- have a clearly defined scope
- preserve architectural consistency
- include deterministic tests
- undergo architecture review
- undergo test review
- avoid unnecessary complexity

---

# Completed

## Phase 1 — Project Foundation

Status: ✅ Completed

Highlights:

- Project setup
- Clean Architecture foundation
- MVVM structure
- Initial dependency injection
- Networking infrastructure

---

## Phase 2 — Repository Search

Status: ✅ Completed

Highlights:

- Search repositories
- Loading state
- Error handling
- Empty state
- Debounced search

---

## Phase 3 — Repository Details

Status: ✅ Completed

Highlights:

- Details screen
- Repository metadata
- Owner information
- Navigation improvements

---

## Phase 4 — Favorites

Status: ✅ Completed

Highlights:

- Favorite repositories
- Local persistence
- Shared synchronization
- Optimistic updates
- Rollback support

---

## Phase 5 — Stability & Concurrency

Status: ✅ Completed

Highlights:

- Structured concurrency improvements
- Cancellation support
- Refresh handling
- Partial failure handling
- Deterministic testing
- Stale response protection
- Architecture refinements

---

# Planned

## Phase 6

Status: ⏳ Planned

Possible improvements:

- Performance optimization
- Additional accessibility improvements
- Better error presentation
- UI polish

Scope will be defined before implementation.

---

## Future Ideas

Possible future enhancements:

- Offline support
- Repository caching
- Image caching
- Advanced search filters
- Search history
- Repository sorting
- User profiles
- Dark mode improvements
- Localization

These items are intentionally not scheduled.

---

# Development Process

Each phase follows:

Planning

↓

Scope Approval

↓

Implementation

↓

Architecture Review

↓

Architecture Approval

↓

Test Review

↓

Merge Review

↓

Commit

Only one phase is active at any time.

Future work must not expand the approved scope.
