# Contributing to ClaudeNotch

Thanks for your interest in contributing! ClaudeNotch is a small, focused project and contributions are welcome.

## Getting Started

1. Fork the repo
2. Clone your fork
3. Build from source:
   ```bash
   swift build
   bash build.sh
   open .build/release/ClaudeNotch.app
   ```

## What We're Looking For

- **Bug fixes** — especially around state detection edge cases
- **New log patterns** — Claude Code's log format evolves; if you spot new patterns that improve state detection, please open a PR
- **MacBook model testing** — we'd love confirmation that the notch alignment works on all MacBook Pro models (14"/16", M1/M2/M3/M4)
- **Battery profiling** — Instruments traces showing energy impact are very welcome

## Code Style

- Swift 6.1, macOS 14+ deployment target
- No third-party dependencies
- Keep it simple — this is a single-purpose utility

## Pull Requests

- Keep PRs small and focused
- Describe what you changed and why
- Test on a real MacBook with a notch if possible

## Reporting Issues

When filing a bug, please include:
- Your MacBook model and macOS version
- A description of what you expected vs what happened
- The last ~20 lines of `~/Library/Logs/Claude/main.log` if relevant (redact any sensitive info)
