# LyricIslandMac

[中文说明](README.zh-CN.md)

LyricIslandMac is a macOS menu bar app that shows synced lyrics in a Dynamic Island style overlay. The app uses native `SwiftUI + AppKit` for the shell and a local `.NET` helper service for lyric lookup.

## Screenshots

### Compact Overlay

![Compact overlay](screenshots/overlay-compact.png)

### Notch Screen Mode

![Notch screen mode](screenshots/overlay-notch-screen.png)

### Menu and Settings

![Menu and settings](screenshots/menu-settings.png)

## Features

- Menu bar app with a notch-inspired lyric overlay
- Default-on floating lyric island at launch
- Compact and expanded display modes
- Fixed target screen selection
- Hover fade effect with click-through overlay behavior
- Spotify playback sync via Web API
- Browser-based Spotify login with PKCE
- Local lyrics resolution through `Lyricify-Lyrics-Helper`
- Multi-source lyric lookup: Spotify, QQ Music, 网易云

## Project Structure

```text
Sources/LyricIslandMac/
  App/        App lifecycle, menu bar UI, app state
  Overlay/    Floating island window and rendering
  Playback/   Spotify auth and playback clients
  Lyrics/     Local helper bridge and lyric providers
  Settings/   Settings window
  Shared/     Shared models

Tests/LyricIslandMacTests/
lyrics-service/LyricIsland.LyricsService/
lyrics-service/vendor/Lyricify.Lyrics.Helper/
```

## Requirements

- macOS 14+
- Xcode with Swift 6 toolchain or a recent SwiftPM toolchain
- .NET SDK for `lyrics-service/LyricIsland.LyricsService`
- A Spotify Developer app with a valid `Client ID`

## Build and Run

Build the Swift app:

```bash
cd /Users/gibara/LyricIslandMac
swift build
```

Run the app from SwiftPM:

```bash
swift run LyricIslandMac
```

Build the local lyrics helper:

```bash
cd /Users/gibara/LyricIslandMac/lyrics-service/LyricIsland.LyricsService
dotnet build
```

Default helper path while developing (bundled helpers are preferred in packaged apps):

```text
lyrics-service/LyricIsland.LyricsService/bin/Debug/net10.0/LyricIsland.LyricsService
```

## Packaging

Build a distributable `.app` bundle:

```bash
./scripts/build_app.sh
```

Build a `.dmg` image:

```bash
./scripts/build_dmg.sh
```

Artifacts are written to `dist/`. The packaged app bundles the local lyrics helper output under `Contents/Resources/LyricsService/`, but the target machine still needs a compatible .NET runtime.

Current GitHub Releases provide an unsigned DMG. On first launch after dragging the app into `Applications`, macOS may block it with a damaged or unidentified developer warning. Remove the quarantine flag once on the target machine:

```bash
xattr -dr com.apple.quarantine /Applications/LyricIslandMac.app
```

If the app is not in `Applications` yet, replace the path with the real location.

### GitHub Actions Release

This repository includes `.github/workflows/release-dmg.yml`.

- Pushing a tag like `v1.0.0` builds the macOS `.dmg`
- The workflow uploads the DMG to the matching GitHub Release
- You can also run it manually from `Actions > Release DMG`
- The workflow uses Node 24 compatible GitHub Actions versions
- The workflow currently builds and uploads an unsigned DMG
- Users may need to run `xattr -dr com.apple.quarantine /Applications/LyricIslandMac.app` once after installation

## Spotify Setup

1. Create or open your app in Spotify Developer Dashboard.
2. Add this Redirect URI exactly:

```text
http://127.0.0.1:766/callback
```

3. Copy the app `Client ID`.
4. Open LyricIslandMac settings and fill the `Client ID`.
5. Click `登录 Spotify` to complete browser authorization.

The app stores the returned refresh token locally and refreshes access tokens automatically on later launches.

## Usage

- The lyric island shows automatically when the app starts.
- Use the menu to switch compact/expanded mode and choose which screen to display on.
- The overlay is click-through, so it will not block interaction with the window underneath.
- Optional `sp_dc` can still be set for helper-side Spotify lyric/search behavior.

## Current Scope

Implemented:

- Real Spotify playback polling
- PKCE-based Spotify login flow
- Menu bar controls for overlay behavior
- Local `.NET` lyrics helper integration

Still incomplete:

- More advanced source ranking and merge logic
- Rich translation/subline composition
- More complete provider integration tests and error diagnostics

## Acknowledgements

Lyric lookup in the local helper is powered by [`Lyricify-Lyrics-Helper`](https://github.com/WXRIW/Lyricify-Lyrics-Helper). The vendored snapshot is `v0.2.0` plus upstream commit `983709b`; it provides the core lyric parsing, search, and provider integration capabilities used by the bundled `.NET` service.
