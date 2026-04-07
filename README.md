<p align="center">
  <h1 align="center">ClaudeNotch</h1>
  <p align="center">
    <strong>Turn your MacBook notch into a live Claude Code status bar.</strong>
  </p>
  <p align="center">
    Tab away. Your notch tells you what Claude is doing.
  </p>
  <p align="center">
    <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/RapidArmageddon/ClaudeNotch?style=flat-square&color=blue" alt="Latest Release"></a>
    <a href="../../releases"><img src="https://img.shields.io/github/downloads/RapidArmageddon/ClaudeNotch/total?style=flat-square&color=green" alt="Downloads"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/RapidArmageddon/ClaudeNotch?style=flat-square" alt="MIT License"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square" alt="macOS 14+">
    <img src="https://img.shields.io/badge/dependencies-zero-orange?style=flat-square" alt="Zero Dependencies">
  </p>
</p>

---

## The Problem

Claude Code takes time to think, run tools, and generate responses. While it works, you're stuck watching a terminal — or you tab away and keep switching back to check if it's done.

## The Solution

ClaudeNotch turns your MacBook's notch into a live status indicator. It seamlessly extends the notch with the current Claude Code state, so you always know what's happening — even while working in other apps.

- **Thinking** — Claude is processing your prompt
- **Bash** / **Read** / **Edit** — Claude is running a specific tool
- **Waiting** — Claude is done, your turn
- **Stopped** — something went wrong

No dock icon. No floating windows. Just your notch, doing more.

## Install

### Download (recommended)

1. Grab `ClaudeNotch.zip` from the [latest release](../../releases/latest)
2. Unzip and drag `ClaudeNotch.app` to `/Applications`
3. Open it — a sparkle icon appears in your menu bar
4. That's it. Open Claude Code and start working.

### Build from source

```bash
git clone https://github.com/RapidArmageddon/ClaudeNotch.git
cd ClaudeNotch
bash build.sh
open .build/release/ClaudeNotch.app
```

Requires Xcode 16+ and macOS 14 Sonoma or later. Zero dependencies.

## How It Works

ClaudeNotch monitors `~/Library/Logs/Claude/main.log` in real-time using macOS kernel events (`kqueue` via `DispatchSource`). It detects state transitions from Claude Code's actual log output — session starts, tool executions, permission requests, query completions, and errors.

No polling loops. No CPU usage when idle. No special permissions required.

### State Detection

| Log Signal | State | Notch Shows |
|---|---|---|
| Session starts | Launching | bolt icon + "Starting" |
| Message sent | Processing | sparkles icon + "Thinking" |
| Tool approved | Processing | gear icon + tool name |
| Permission needed | Waiting | hand icon + "Waiting" |
| Query complete | Waiting | hand icon + "Waiting" |
| Session idle | Idle | notch returns to normal |
| Unhealthy cycle | Error | warning icon + "Stopped" |

### Energy Efficiency

ClaudeNotch is designed to be invisible to your battery:

- **When Claude is not running:** Zero CPU, zero GPU. Only dormant kernel event watchers and two NSWorkspace notification observers.
- **When Claude is active:** Log reads on state changes (microseconds of work). Pulse animation runs at 2 fps via `TimelineView`, not 120 fps via `CADisplayLink`.
- **When idle:** Window is ordered out of the compositor entirely — no rendering cost.

## Compatibility

| Device | Support |
|---|---|
| MacBook Pro 14" / 16" (M1–M4, 2021+) | Full — pill extends from the notch |
| MacBook Air / older MacBook | Floating pill at top of screen |
| External monitors | Pill stays on the built-in notch display |

## Architecture

```
ClaudeNotchApp (LSUIElement — no dock icon)
├── ClaudeStateMonitor     — tails main.log + NSWorkspace notifications
├── NotchWindowController  — borderless NSWindow in the notch
│   └── NotchPillView      — SwiftUI view with state-driven content
├── MenuBarController      — status bar icon + quit menu
└── ClaudeState            — enum: idle | launching | processing | waiting | error
```

Six files. ~500 lines of Swift. Zero dependencies.

## FAQ

**Does it need any permissions?**
No. It reads a log file in your home directory and observes running processes — both are standard macOS APIs that require no entitlements.

**Does it work with Claude Code in the terminal?**
Currently it monitors the Claude Desktop app's log file (`~/Library/Logs/Claude/main.log`). Terminal-only Claude Code support is planned.

**Will it conflict with other notch apps?**
It shouldn't — ClaudeNotch uses its own `NSWindow` at a high window level. If you see conflicts, please open an issue.

**How do I quit it?**
Click the sparkle icon in your menu bar and select "Quit".

**Does it phone home or collect data?**
No. It reads one local log file. No network requests, no analytics, no telemetry. Check the source — it's 500 lines.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports, new log pattern discoveries, and MacBook model testing are especially welcome.

## License

[MIT](LICENSE) — do whatever you want with it.

---

<p align="center">
  <sub>Built for the Claude Code community. If this saves you even one tab switch, consider leaving a star.</sub>
</p>
