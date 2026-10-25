# Pinfall Rescue — iOS app

WKWebView shell around the tested web game (`Pinfall/game.html`).
Fully offline: no permissions, no network, progress saved on-device.

- Bundle id: `com.pinfall.rescue` (same as Android, for a consistent store presence)
- Version: 1.0 (build 1)
- Deployment target: iOS 16, iPhone + iPad (portrait)
- Icon: goblin + gold coins, all sizes in `Assets.xcassets`

## Why this builds on a Mac, not here

iOS apps can only be compiled with Xcode, which only runs on macOS, and the
iOS SDK is Apple-proprietary. This Linux machine cannot build or download
Xcode (it would not run here even if downloaded). So: this folder is the
complete, ready-to-open Xcode project — the Mac does the compiling.

## Build on your Mac

1. Install Xcode from the Mac App Store (free; ~15 GB).
2. Copy this folder to the Mac, open `Pinfall.xcodeproj`.
3. Signing & Capabilities → Team → pick your Apple ID (free tier runs on your
   own devices; App Store distribution needs the Apple Developer Program,
   $99/year).
4. Pick a simulator and press Run, or `./build.sh` for a command-line build
   and `./build.sh archive` for a release archive.

## App Store release path

1. Archive in Xcode → Distribute App → App Store Connect.
2. In App Store Connect: screenshots (iPhone + iPad), description, category
   (Games → Puzzle), age rating questionnaire, privacy policy URL
   (the game collects nothing; reuse the Android `PRIVACY_POLICY.md` text).
3. Submit for review.

## Reuse for the next game

Copy this folder, then change four things: replace `Pinfall/game.html` with
the new game, replace the icons in `Assets.xcassets`, change
`PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`, and change the display name
in `Info.plist` + the launch screen text. Everything else (WebView shell,
portrait lock, offline setup) stays the same.

## Swapping in the real-art version

`Pinfall/game.html` is currently the approved code-drawn version (the same one
in the Android APK). If the real-art build (`pinfall-rescue-real-art.html`)
wins the art comparison, just copy it over `game.html` and rebuild — no code
changes needed.
