# CLI Terminal Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the notch pill activate the correct app (Terminal.app or Claude Desktop) based on which session type was most recently active.

**Architecture:** Add a `SessionSource` enum to ClaudeStateMonitor that tracks whether the latest activity came from a CLI or Desktop session, determined by log line prefixes. NotchPillView reads this to decide which bundle ID to activate on click.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit (NSRunningApplication)

---

### Task 1: Add SessionSource enum and property to ClaudeStateMonitor

**Files:**
- Modify: `Sources/ClaudeStateMonitor.swift:82-86`

**Step 1: Add the enum and published property**

Add `SessionSource` enum before the class, and add the published property alongside the existing ones:

```swift
enum SessionSource {
    case desktop
    case cli
}
```

Inside `ClaudeStateMonitor`, after line 86 (`@Published private(set) var isPermissionRequest: Bool = false`), add:

```swift
@Published private(set) var activeSessionSource: SessionSource = .desktop
```

**Step 2: Build to verify it compiles**

Run: `swift build -c release 2>&1`
Expected: Build complete

**Step 3: Commit**

```bash
git add Sources/ClaudeStateMonitor.swift
git commit -m "feat: add SessionSource enum to ClaudeStateMonitor"
```

---

### Task 2: Update log parsing to track session source

**Files:**
- Modify: `Sources/ClaudeStateMonitor.swift:269-338` (parseLogLine method)

**Step 1: Set source to .cli for CLI log patterns**

In `parseLogLine`, the existing block at line 286-290 handles `LocalAgentModeSessions.start`:

```swift
if line.contains("LocalAgentModeSessions.start") {
    hasActiveSession = true
    startLaunchingTimeout()
    transition(to: .launching)
    return
}
```

Change to:

```swift
if line.contains("LocalAgentModeSessions.start") {
    hasActiveSession = true
    activeSessionSource = .cli
    startLaunchingTimeout()
    transition(to: .launching)
    return
}
```

**Step 2: Add CLI sendMessage detection before the existing Desktop sendMessage block**

The existing block at line 293-298 catches `LocalSessions.sendMessage`. This also matches `LocalAgentModeSessions.sendMessage` since it contains the substring. Add a more specific check *before* it:

```swift
if line.contains("LocalAgentModeSessions.sendMessage") {
    hasActiveSession = true
    activeSessionSource = .cli
    cancelLaunchingTimeout()
    isPermissionRequest = false
    transition(to: .processing(tool: nil))
    return
}
```

Then update the existing `LocalSessions.sendMessage` block to also set the source:

```swift
if line.contains("LocalSessions.sendMessage") {
    hasActiveSession = true
    activeSessionSource = .desktop
    cancelLaunchingTimeout()
    isPermissionRequest = false
    transition(to: .processing(tool: nil))
    return
}
```

**Important:** The `LocalAgentModeSessions.sendMessage` check MUST come before `LocalSessions.sendMessage` because the latter is a substring of the former.

**Step 3: Build to verify**

Run: `swift build -c release 2>&1`
Expected: Build complete

**Step 4: Commit**

```bash
git add Sources/ClaudeStateMonitor.swift
git commit -m "feat: track session source from log patterns"
```

---

### Task 3: Update NotchPillView click activation to use session source

**Files:**
- Modify: `Sources/NotchPillView.swift:98,116,143-149`

**Step 1: Change activateClaude from static to instance method**

Replace the current static method (lines 143-149):

```swift
// MARK: - Click to Activate Claude

private static func activateClaude() {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop")
    guard let claude = apps.first else { return }
    claude.activate()
}
```

With an instance method that reads `monitor.activeSessionSource`:

```swift
// MARK: - Click to Activate Claude

private func activateClaude() {
    let bundleId: String
    switch monitor.activeSessionSource {
    case .desktop:
        bundleId = "com.anthropic.claudefordesktop"
    case .cli:
        bundleId = "com.apple.Terminal"
    }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
    app.activate()
}
```

**Step 2: Update tap gesture calls from Self.activateClaude() to self.activateClaude()**

Line 98 — change:
```swift
.onTapGesture { Self.activateClaude() }
```
to:
```swift
.onTapGesture { self.activateClaude() }
```

Line 116 — same change:
```swift
.onTapGesture { Self.activateClaude() }
```
to:
```swift
.onTapGesture { self.activateClaude() }
```

**Step 3: Build to verify**

Run: `swift build -c release 2>&1`
Expected: Build complete

**Step 4: Build app bundle and test**

Run: `bash build.sh 2>&1`
Expected: App bundle created

**Step 5: Commit**

```bash
git add Sources/NotchPillView.swift
git commit -m "feat: activate Terminal or Desktop based on session source"
```

---

### Task 4: Manual integration test

**Step 1: Launch the app**

Run: `open .build/release/ClaudeNotch.app`

**Step 2: Test Desktop mode**

- Open Claude Desktop, start a conversation
- Click the notch pill → Claude Desktop should come to foreground

**Step 3: Test CLI mode**

- Open Terminal.app, run `claude` to start a Claude Code session
- Send a message so the pill activates
- Click the notch pill → Terminal.app should come to foreground

**Step 4: Test switching**

- With both active, send a message in the Desktop app → click pill → Desktop activates
- Send a message in the CLI → click pill → Terminal activates
