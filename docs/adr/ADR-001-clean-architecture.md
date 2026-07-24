# ADR-001: Adopt Clean Architecture

## Status

Accepted

## Context

The application is expected to grow over time with additional features, asynchronous workflows, and multiple data sources.

Without clear boundaries, business logic can easily leak into UI or networking code, making testing and maintenance more difficult.

## Decision

The project adopts Clean Architecture.

The application is divided into three layers:

- Presentation
- Domain
- Data

Dependencies always point toward the Domain layer.

## Consequences

### Advantages

- Better separation of concerns
- Easier testing
- Independent business logic
- Replaceable implementations
- Scalable architecture

### Trade-offs

- More files
- Slightly higher initial complexity
- Requires disciplined dependency management
