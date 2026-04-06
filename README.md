# ClaudeTakip

A macOS menu bar app that tracks your Claude AI usage limits in real time.

## Features

- **Real-time usage tracking** — monitors your 5-hour session and 7-day weekly limits
- **Model-specific tracking** — separate Sonnet usage bar with reset countdown
- **Extra usage monitoring** — tracks overage billing balance and spending
- **AI-powered pacing** — intelligent recommendations based on your usage velocity
- **Usage rate analysis** — speedometer gauges showing session and weekly pace
- **Interactive charts** — detailed usage history with session and weekly views
- **Auto-session** — automatically starts a new session window when the current one expires
- **System status** — live Claude API status indicator
- **14 languages** — English, Turkish, Spanish, French, German, Italian, Dutch, Japanese, Korean, Simplified Chinese, Traditional Chinese, Russian, Arabic, Portuguese (BR)
- **Dark mode** — follows system appearance, configurable per-app
- **Auto-update** — built-in update mechanism via Sparkle

## Requirements

- macOS 15.0 Sequoia or later

## Installation

### DMG

Download the latest `.dmg` from [Releases](https://github.com/BatuhanAkpunar/ClaudeTakip/releases), open it, and drag ClaudeTakip to your Applications folder.

## Usage

1. Click the ClaudeTakip icon in your menu bar
2. Sign in with your Claude account (email or Google)
3. Your usage limits, pacing, and history are displayed automatically

## How It Works

ClaudeTakip reads your usage data from your Claude account and displays it in a compact menu bar dashboard. It polls your usage every 3 minutes and provides AI-powered recommendations to help you manage your limits effectively.

**No data is collected or sent to third parties.** All usage data stays on your device.

## Build from Source

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project and build
xcodegen generate
xcodebuild -project ClaudeTakip.xcodeproj -scheme ClaudeTakip -configuration Release build
```

Requires Xcode 16+ and Swift 6.

## Privacy

- ClaudeTakip only communicates with `claude.ai` (your usage data) and `status.claude.com` (system status)
- AI recommendations are generated via Groq API using anonymized usage percentages only
- Credentials are stored locally on your device with restricted file permissions
- No analytics, telemetry, or tracking of any kind

## License

All rights reserved. See [LICENSE](LICENSE) for details.

## Author

**Batuhan Akpunar** — [LinkedIn](https://www.linkedin.com/in/batuhanakpunar/)
