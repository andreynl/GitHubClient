# Contributing to GitHubClient

GitHubClient is developed in small, reviewed phases. Contributions should keep
their scope explicit and preserve the implemented dependency boundaries
described in [ARCHITECTURE.md](ARCHITECTURE.md) and
[docs/adr](docs/adr/).

## Workflow

For feature work:

1. document the proposed scope;
2. obtain scope approval;
3. implement only the approved behavior;
4. review architecture and concurrency implications;
5. review tests and regressions;
6. validate the complete diff;
7. commit only after approval.

Documentation and repository-maintenance changes may use the same review and
validation steps without inventing a product phase.

## Scope

- Keep each change focused.
- Avoid unrelated refactoring and formatting churn.
- Do not combine product behavior, architecture migration, and documentation
  cleanup in one commit.
- Update public documentation when verified behavior or architecture changes.

## Architecture

- Views render state and forward actions; they do not access networking or
  persistence directly.
- ViewModels depend on Domain repository protocols.
- Concrete networking, cache, and persistence implementations remain in Data.
- DTOs do not leave Data.
- Dependency construction remains in `AppContainer`.
- `FavoritesStore` remains the shared source of favorite IDs across features.

The folders are not separate Swift modules, so these rules are maintained by
review and tests.

## Swift and Concurrency

- Preserve the existing 2-space Swift indentation.
- Avoid force unwraps and force casts.
- Keep UI state and observable ViewModels on `MainActor`.
- Own and cancel long-lived tasks explicitly.
- Protect state from stale asynchronous completions.
- Prefer `async`/`await` and task groups over blocking synchronization.
- Do not add `Task.detached` without a documented ownership requirement.

## Testing

The test target uses Swift Testing.

Changes should add focused coverage for affected behavior, including relevant
success, failure, cancellation, retry, refresh, stale-response, or concurrency
paths.

Prefer controlled fakes and continuations. Do not add new tests whose
correctness depends only on an arbitrary delay. Existing bounded polling and
short-delay tests are known technical debt; changing them belongs in an
approved hardening scope.

Persistence tests must use isolated UserDefaults suites and clean their
persistent domains.

Cache tests must use the injected cache clock instead of waiting for wall-clock
time. Existing bounded polling and a small number of legacy delay-driven
concurrency tests remain documented debt; new ordering tests must use
controlled synchronization.

## Validation

Discover available simulators before testing:

```bash
xcrun simctl list devices available
```

Build:

```bash
xcodebuild \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`CODE_SIGNING_ALLOWED=NO` is appropriate for compilation, analyzer, and unit
test validation. Do not install that unsigned product to validate native Launch
Screen behavior: unsigned Simulator builds can trigger a SplashBoard security
fallback. Validate the Launch Screen with a normally signed Simulator build.

Run tests using an available simulator:

```bash
xcodebuild \
  -project GitHubClient.xcodeproj \
  -scheme GitHubClient \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Also run:

```bash
git diff --check
git status --short --branch
```

Run `xcodebuild analyze` with the same project, scheme, destination, and
warnings-as-errors settings before public-release changes. Report test counts
and any compiler or analyzer warnings. Do not stage, commit, amend, or push
unless the task explicitly authorizes it.

## Git Hygiene

- Do not commit `xcuserdata`, `.xcuserstate`, DerivedData, `.DS_Store`, result
  bundles, or temporary files.
- Stage explicit paths instead of broad staging commands.
- Keep commits cohesive and descriptive.
- Do not rewrite history or force-push unless explicitly requested.

Project-specific AI instructions are in [AGENTS.md](AGENTS.md).
