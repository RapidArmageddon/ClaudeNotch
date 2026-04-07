# ClaudeNotch

A macOS menu bar app that turns your MacBook's notch into a live Claude Code status indicator.

When Claude Code is active, the notch extends with an icon on the left and status text on the right — seamlessly blending with the physical notch.

## States

| State | Icon | Label |
|---|---|---|
| Starting | bolt | Starting... |
| Thinking | sparkles | Thinking... |
| Running tool | gearshape | Running [tool] |
| Waiting for input | hand.raised | Waiting |
| Error | warning | Stopped |

## Requirements

- macOS 14 Sonoma or later
- MacBook with notch (works on non-notch Macs as a floating pill)
- Claude Code (desktop app)

## Install from Release

1. Download `ClaudeNotch.zip` from the latest [release](../../releases)
2. Unzip and move `ClaudeNotch.app` to `/Applications`
3. Launch it — a sparkle icon appears in your menu bar
4. Open Claude Code and start working

## Build from Source

```bash
git clone https://github.com/yourusername/ClaudeNotch.git
cd ClaudeNotch
bash build.sh
open .build/release/ClaudeNotch.app
```

## How It Works

ClaudeNotch tails `~/Library/Logs/Claude/main.log` to detect Claude Code's state transitions in real-time. No special permissions needed — it reads the log file and polls `NSWorkspace` for process detection.

## License

MIT
