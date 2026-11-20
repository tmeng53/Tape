# Working on Tape

Rules for anyone changing this repo, human or agent. They follow Apple's docs, the Swift project and well-run open-source Mac apps. The research behind them, with sources, is linked from the PR that added this file.

## Build and check

- Requirements: macOS 26, Xcode 26 (Swift 6.3 toolchain).
- Core tests: `swift test --package-path Packages/TapeKit`
- Format: `swift format -i -r Tape Packages`
- Lint: `swift format lint --strict -r Tape Packages`
- App build: `xcodebuild -project Tape.xcodeproj -scheme Tape -destination 'platform=macOS' build`
- CI runs the comment check, lint, core tests and the app build on every push. Keep it green.

## Project rules

- No code comments. Names and small functions carry the meaning. `scripts/check-no-comments.sh` enforces it.
- Delete legacy code instead of patching around it.
- Keep dependencies minimal. Anything new goes to a human first.
- `TapeCore` is vendor-free and imports only Foundation. Every OS or vendor API sits behind a port in `TapeCore` with an adapter in `TapeMac` or a later adapter module.
- Important data is append-only and replayable. Every stored format has a `schemaVersion`. Changes ship as real migrations. Never delete user clips without explicit approval.
- Fix forward. Every bug fix also adds a test or static check so it cannot come back.
- Tests from day one, proportionate to risk. Expensive suites run only on request.
- UI uses existing system and design-system components. New UI gets a prototype and approval first.
- When the design gets in your way, open a `friction` issue and keep going.

## Swift

- Swift 6 language mode in every target, with complete concurrency checking. Never use `.swiftLanguageMode(.v5)`.
- Default isolation: the app target and UI code are `@MainActor` by default. `TapeCore` stays nonisolated and is mostly value types, so it is easy to test.
- Shared mutable state lives in an actor, on the main actor, or behind `Mutex` from the Synchronization framework. Avoid `@unchecked Sendable`; when a system type forces it, keep the type tiny and its state behind a `Mutex`.
- Events that must stay in order, such as key-tap actions, go through one `AsyncStream` with one consumer. Never start a `Task` per event.
- Every unstructured `Task` has an owner that stores and cancels it.
- Wrap callback and delegate APIs once, in the adapter, as `async` functions.
- Follow the Swift API Design Guidelines: clarity at the point of use, no abbreviations, protocols named for capability.
- Value types by default, `final class` when identity matters. `private` by default, `public` only for what another module uses.
- No `!` force unwraps, `as!` or `try!` outside tests. Tests use `#require`.
- Never swallow a failure that matters with `try?`. Throw a domain error or log it.
- Log with `os.Logger` (subsystem `app.tape.mac`, one category per area). No `print`. User content stays private in logs, which is the default.
- State that the UI watches uses Observation (`@Observable`), not `ObservableObject` or Combine.
- User-facing text lives in a String Catalog. Build sentences with interpolation, never by gluing fragments.

## The Mac app

- SwiftUI first. AppKit where SwiftUI cannot do it: event taps, the notch panel, Accessibility, pasteboard.
- Tape is a menu bar agent (`LSUIElement`). Startup work runs in an `NSApplicationDelegateAdaptor`, not in a view's `.task`.
- Settings use a SwiftUI `Settings` scene and follow the macOS settings layout.
- Launch at login uses `SMAppService.mainApp`, opt-in, never on by default.
- Permissions: ask at the moment of need, after a one-line why. Read the state every time, because people revoke access. Link straight to the right System Settings pane. Screen Recording asks again periodically on macOS 15 and later; treat that as normal, not as an error.
- Event tap callbacks return fast and never block. Re-enable the tap when macOS disables it on timeout.
- Respect Reduce Motion and Increase Contrast. Every control has a VoiceOver label.
- Distribution: Hardened Runtime on, Developer ID signing, notarized and stapled. Tape is not sandboxed because Accessibility and event taps do not work inside the App Sandbox, so it ships outside the Mac App Store. Entitlements stay minimal.
- Privacy: no network calls in the MVP. Clips stay in `~/Library/Application Support/Tape`. Never-capture apps stay out of recordings.

## Tests

- Swift Testing (`@Test`, `#expect`, `#require`) for all unit tests. XCTest only for UI or performance tests.
- Logic lives in `TapeCore` and is tested with fakes for its ports.
- Mac-only behaviour (permissions, event tap, capture, paste) is checked on a real Mac against a written checklist in the PR.

## Commits and PRs

- Conventional Commits: `feat:`, `fix:`, `ci:`, `docs:`, `refactor:`, `test:`.
- One owner per PR, no stacked PRs, squash merge only.
- Request codex review once a version is ready. Treat findings as symptoms of the design.
- Owners merge low-risk PRs when CI is green and review is clean. Risky or one-way changes also need an independent reviewer and a human's go.
