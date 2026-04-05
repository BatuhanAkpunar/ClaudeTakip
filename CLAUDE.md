# CLAUDE.md

## Project Overview

**ClaudeTakip** is a macOS menu bar app that tracks Claude AI usage limits.

- **Language:** Swift 6
- **Frameworks:** AppKit + SwiftUI
- **Min macOS:** 15.0 Sequoia
- **Distribution:** DMG + Homebrew
- **Dependencies:** Sparkle (auto-update)

## Build & Run

```bash
xcodegen generate
xcodebuild -project ClaudeTakip.xcodeproj -scheme ClaudeTakip -configuration Debug build
xcodebuild -project ClaudeTakip.xcodeproj -scheme ClaudeTakip test
```

## Architecture

- Menu bar only app (LSUIElement = true)
- AppDelegate: central coordinator, owns all managers
- AppState: @Observable single source of truth
- Auth: WKWebView cookie extraction from claude.ai
- Usage: polls claude.ai/api/organizations/{orgId}/usage every 3 minutes
- Pacing: deviation-based velocity tracking algorithm
- Notes: UserDefaults persistence
- Credentials: macOS Keychain

## Code Conventions

- Swift 6 strict concurrency
- @MainActor for all UI-touching code
- LocalizedStringKey for all UI strings
- DesignTokens (DT.*) for all colors, fonts, spacing
- No emojis in UI
