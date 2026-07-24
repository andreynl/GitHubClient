# ADR-002: Use Repository Pattern

## Status

Accepted

## Context

ViewModels require data from different sources without depending on networking or persistence details.

## Decision

All data access is performed through repository protocols defined in the Domain layer.

Concrete implementations live in the Data layer.

## Consequences

### Advantages

- Loose coupling
- Testability
- Easier mocking
- Future persistence changes remain isolated

### Trade-offs

- Additional abstraction
- Slight increase in boilerplate
