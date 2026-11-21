# Tape

Hold a key, talk to your screen, let go. Tape records your screen, cursor and voice and drops the clip into whatever text box you were working in, so a coding agent (or a teammate) sees exactly what you mean.

Status: early. Milestone 1, the walking skeleton.

## Requirements

- macOS 26 or later
- Xcode 26

## Build and run

1. Clone and open `Tape.xcodeproj`.
2. Create `Config/Local.xcconfig` with your Apple Development team so macOS keeps Tape's permissions across rebuilds:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```

   Your team id is in Xcode > Settings > Accounts. A free Personal Team works.
3. Press Run. Tape lives in the menu bar and asks for Accessibility, Screen Recording and Microphone.

Core tests: `swift test --package-path Packages/TapeKit`

## How it works

- Hold left ⌃ to talk, release to drop the clip into the focused text box.
- Tap left ⌃ to record hands-free, tap again to stop.
- Esc cancels; the clip is kept in the clips folder.
- With no text box focused, the clip is copied: press ⌘V where you want it.

Clips live in `~/Library/Application Support/Tape/Clips`, one folder per clip.

## Layout

- `Tape/` the app: menu bar UI and wiring.
- `Packages/TapeKit/Sources/TapeCore` vendor-free logic: talk key gestures, paste fallback order, clip model, recording session.
- `Packages/TapeKit/Sources/TapeMac` macOS adapters: event tap, ScreenCaptureKit, Accessibility, pasteboard.

## License

AGPL-3.0
