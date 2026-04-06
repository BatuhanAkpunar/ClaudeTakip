# CLAUDE.md

## Project Overview

**ClaudeTakip** is a macOS menu bar app that tracks Claude AI usage limits in real time.

- **Language:** Swift 6 (strict concurrency)
- **Frameworks:** AppKit + SwiftUI
- **Min macOS:** 15.0 Sequoia
- **Distribution:** DMG + Sparkle auto-update
- **Dependencies:** Sparkle 2.8+
- **Localization:** 14 languages (en, tr, es, fr, de, it, nl, ja, ko, zh-Hans, zh-Hant, ru, ar, pt-BR)

## Build & Run

```bash
xcodegen generate
xcodebuild -project ClaudeTakip.xcodeproj -scheme ClaudeTakip -configuration Debug build
```

## Architecture

- **Menu bar only** (LSUIElement = true, no Dock icon)
- **AppDelegate** — central coordinator, owns all managers and services
- **AppState** — `@Observable` single source of truth for all UI state
- **AuthManager** — WKWebView cookie extraction from claude.ai, Google OAuth support
- **UsageService** — polls claude.ai API every 3 minutes, caches to disk; fetches account profile from `/api/account` (email, display name) and org details from `/api/organizations`
- **UsageCacheStore** — per-user (orgId-scoped) file-based cache in Application Support
- **PacingEngine** — deviation-based velocity tracking with 6 severity levels
- **PacingMessageService** — AI-powered recommendations via Groq API (llama-4-scout)
- **AutoSessionService** — auto-starts new sessions using Haiku when window expires
- **StatusService** — monitors claude.ai system status every 15 minutes
- **NotesManager** — user settings persistence via UserDefaults
- **Credentials** — file-based storage in `~/Library/Application Support/ClaudeTakip/.credentials` (POSIX 0600)

## Key Design Decisions

- **No macOS Keychain** — file-based credential storage avoids code-signature ACL prompts with ad-hoc signing
- **Per-user data isolation** — cache files scoped by orgId to prevent data leakage between accounts
- **First-launch defaults** — detects OS dark mode and language, saves explicitly
- **Groq debounce** — 30s debounce on state changes, 1h cache window, max 5 consecutive errors before blocking; skips API calls when AI Recommendation setting is disabled

## Code Conventions

- Swift 6 strict concurrency
- `@MainActor` for all UI-touching code
- `String(localized:bundle:.app)` for all UI strings
- `DesignTokens (DT.*)` for all colors, fonts, spacing
- No emojis in UI
- Ad-hoc code signing (`CODE_SIGN_IDENTITY: "-"`)
