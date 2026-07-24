# ADR-006: Feature-Based Project Structure

## Status

Accepted

## Context

As the application grows, organizing code by technical layer alone makes navigation harder.

## Decision

The project is organized primarily by feature.

Shared code lives in the Shared module.

## Consequences

### Advantages

- Better discoverability
- Easier feature ownership
- Reduced coupling between features

### Trade-offs

- Shared code requires discipline to avoid becoming a dumping ground
