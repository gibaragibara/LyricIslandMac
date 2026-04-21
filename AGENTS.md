# Repository Guidelines

## Project Structure & Module Organization
`Sources/LyricIslandMac/` contains the macOS app, split by feature: `App/` for app state and menu bar entry points, `Overlay/` for the lyric UI, `Playback/` for Spotify integration, `Lyrics/` for the helper bridge, `Settings/` for preferences, and `Shared/` for cross-cutting models. Tests live in `Tests/LyricIslandMacTests/`. The local lyrics backend is under `lyrics-service/LyricIsland.LyricsService/`, with vendored provider code in `lyrics-service/vendor/`.

## Build, Test, and Development Commands
Run commands from the repository root unless noted.

- `swift build` builds the macOS executable target defined in `Package.swift`.
- `swift run LyricIslandMac` launches the app from the Swift package.
- `swift test` runs the Swift test target in `Tests/LyricIslandMacTests/`.
- `cd lyrics-service/LyricIsland.LyricsService && dotnet build` builds the local helper used by `DotnetLyricsServiceClient`.

The Swift app expects the helper DLL at `lyrics-service/LyricIsland.LyricsService/bin/Debug/net10.0/LyricIsland.LyricsService.dll` unless settings override it.

## Coding Style & Naming Conventions
Follow standard Swift 6 conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods, and one primary type per file named after that type, such as `AppModel.swift`. Keep feature code in its existing folder instead of creating generic utility buckets. For the .NET helper, match the existing C# style: nullable enabled, `PascalCase` public members, and focused files under `LyricIsland.LyricsService/`.

No formatter or linter config is checked in, so use Xcode or SwiftPM default formatting and keep diffs minimal.

## Testing Guidelines
Swift tests use Apple’s `Testing` package (`import Testing`, `@Test`). Add or update tests when changing playback parsing, lyric payload mapping, or settings persistence. Prefer test names that describe behavior, for example `@Test func fetchLyricsReturnsPayloadForSpotifyTrack()`. No coverage threshold is defined, but new logic should ship with focused tests.

## Commit & Pull Request Guidelines
Git history is not available in this checkout, so use short imperative commit subjects, for example `Add helper path validation`. Keep commits scoped to one concern. Pull requests should explain user-visible changes, list build/test commands run, reference related issues, and include screenshots for overlay or settings UI changes.

## Security & Configuration Tips
Do not commit Spotify credentials, `.netrc`, or local build outputs such as `.build/`, `bin/`, and `obj/`. Keep machine-specific helper paths in local settings, not source files.
