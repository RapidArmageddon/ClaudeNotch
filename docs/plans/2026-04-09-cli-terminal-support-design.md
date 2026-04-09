# Claude Code Terminal Support

**Date:** 2026-04-09
**Status:** Approved

## Problem

ClaudeNotch only activates Claude Desktop on click. Users running Claude Code in Terminal.app need the notch pill to bring the terminal forward instead.

## Approach: Log-based session type tracking

Both CLI and Desktop sessions write to the same log (`~/Library/Logs/Claude/main.log`) with distinguishable prefixes:

- **Desktop:** `LocalSessions.sendMessage`
- **CLI:** `LocalAgentModeSessions.sendMessage`

Track the most recently active session source and activate the corresponding app on click.

## Design

### SessionSource enum (ClaudeStateMonitor)

```swift
enum SessionSource {
    case desktop   // LocalSessions.sendMessage
    case cli       // LocalAgentModeSessions.sendMessage
}

@Published private(set) var activeSessionSource: SessionSource = .desktop
```

### Log parsing changes (ClaudeStateMonitor.parseLogLine)

- `LocalAgentModeSessions.sendMessage` → set `activeSessionSource = .cli`
- `LocalAgentModeSessions.start` → set `activeSessionSource = .cli`
- `LocalSessions.sendMessage` → set `activeSessionSource = .desktop`

### Click activation (NotchPillView)

- Convert `activateClaude()` from static to instance method (needs monitor access)
- `.cli` → activate `com.apple.Terminal`
- `.desktop` → activate `com.anthropic.claudefordesktop`

### Idle detection

No changes needed. Existing behavior (pill hides on Desktop app termination, shows on any session activity) works for both session types.

## Files modified

1. `Sources/ClaudeStateMonitor.swift` — SessionSource enum, published property, parsing
2. `Sources/NotchPillView.swift` — instance-based activation, bundle ID switching
