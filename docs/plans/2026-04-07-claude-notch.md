# ClaudeNotch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone macOS app that overlays the MacBook notch with a Dynamic Island-style pill showing Claude Code's live state.

**Architecture:** LSUIElement app with a borderless NSWindow positioned in the notch, hosting a SwiftUI pill view. State detection via tailing `~/Library/Logs/Claude/main.log` for session events, with NSWorkspace process detection as presence check. Menu bar icon for quit/settings.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, Combine, DispatchSource, macOS 14+ deployment target

**Compatibility:** All MacBook models — notch models (14"/16" 2021+) get the pill in the notch; non-notch models and external displays get the pill floating at top-centre. Screen detection via `NSScreen.auxiliaryTopLeftArea` (macOS 14+) to detect notch presence.

---

### Task 1: Create Xcode Project

**Files:**
- Create: `ClaudeNotch.xcodeproj` (via xcodebuild)
- Create: `ClaudeNotch/ClaudeNotchApp.swift`
- Create: `ClaudeNotch/Info.plist`

**Step 1: Create the project directory structure**

```bash
mkdir -p ClaudeNotch
```

**Step 2: Create a minimal Swift Package-based app using `swift package init` or manual project**

Since we need an `.app` bundle with `Info.plist` (for `LSUIElement`), create the Xcode project manually with these files:

`ClaudeNotch/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>ClaudeNotch</string>
    <key>CFBundleIdentifier</key>
    <string>com.louisdeleuil.claudenotch</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

`ClaudeNotch/ClaudeNotchApp.swift` (minimal entry point):
```swift
import SwiftUI

@main
struct ClaudeNotchApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

**Step 3: Create the Xcode project file**

Use a `Package.swift` or generate `.xcodeproj`. Since this is a macOS app bundle, the simplest approach is to create a `Package.swift` that builds an executable, then wrap it with a shell script that creates the `.app` bundle with the Info.plist. Alternatively, generate the `.xcodeproj` using `xcodegen` or create it manually.

Recommended: Use Xcode project generation via a `project.yml` for XcodeGen, or create the project programmatically.

**Step 4: Verify it builds and launches with no Dock icon**

```bash
cd ClaudeNotch
xcodebuild -scheme ClaudeNotch -configuration Debug build
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: initial ClaudeNotch project with LSUIElement"
```

---

### Task 2: ClaudeState Enum

**Files:**
- Create: `ClaudeNotch/ClaudeState.swift`

**Step 1: Define the state enum**

```swift
import Foundation

enum ClaudeState: Equatable {
    case idle
    case launching
    case processing(tool: String?)
    case waitingForInput
    case error(message: String)

    // Equatable conformance for associated values
    static func == (lhs: ClaudeState, rhs: ClaudeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.launching, .launching),
             (.waitingForInput, .waitingForInput):
            return true
        case let (.processing(a), .processing(b)):
            return a == b
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeNotch/ClaudeState.swift
git commit -m "feat: add ClaudeState enum"
```

---

### Task 3: ClaudeStateMonitor — Log Tailer + Process Watcher

**Files:**
- Create: `ClaudeNotch/ClaudeStateMonitor.swift`

This is the most critical component. It watches `~/Library/Logs/Claude/main.log` by tailing new lines via `DispatchSource`, and polls `NSWorkspace` for Claude.app process presence.

**Step 1: Implement ClaudeStateMonitor**

```swift
import Foundation
import Combine
import AppKit

@MainActor
final class ClaudeStateMonitor: ObservableObject {
    @Published private(set) var state: ClaudeState = .idle

    private var processTimer: Timer?
    private var logSource: DispatchSourceFileSystemObject?
    private var logFileHandle: FileHandle?
    private var lastFileOffset: UInt64 = 0
    private var claudeIsRunning = false

    // Track active session to know when we have one
    private var hasActiveSession = false

    private let logPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/Claude/main.log"
    }()

    func startMonitoring() {
        // Poll for Claude.app process every 2s
        processTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollForProcess() }
        }
        processTimer?.fire()

        startLogWatcher()
    }

    func stopMonitoring() {
        processTimer?.invalidate()
        processTimer = nil
        stopLogWatcher()
    }

    // MARK: - Process Detection

    private func pollForProcess() {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.anthropic.claude"
        }

        if isRunning && !claudeIsRunning {
            claudeIsRunning = true
            // Don't transition yet — wait for session signals from logs
        } else if !isRunning && claudeIsRunning {
            claudeIsRunning = false
            hasActiveSession = false
            transition(to: .idle)
        }
    }

    // MARK: - Log Watching

    private func startLogWatcher() {
        guard FileManager.default.fileExists(atPath: logPath) else { return }

        let fd = open(logPath, O_RDONLY)
        guard fd >= 0 else { return }

        // Seek to end — only read new lines
        logFileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let endOffset = logFileHandle?.seekToEndOfFile() ?? 0
        lastFileOffset = endOffset

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            self?.readNewLogLines()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        logSource = source
    }

    private func stopLogWatcher() {
        logSource?.cancel()
        logSource = nil
        logFileHandle = nil
    }

    private func readNewLogLines() {
        guard let handle = logFileHandle else { return }

        handle.seek(toFileOffset: lastFileOffset)
        let data = handle.readDataToEndOfFile()
        lastFileOffset = handle.offsetInFile

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8)
        else { return }

        let lines = text.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseLogLine(line)
        }
    }

    // MARK: - Log Parsing

    private func parseLogLine(_ line: String) {
        // Session starting
        if line.contains("LocalSessions.start") {
            Task { @MainActor in
                hasActiveSession = true
                transition(to: .launching)
            }
            return
        }

        // User sent a message → processing
        if line.contains("LocalSessions.sendMessage") {
            Task { @MainActor in
                hasActiveSession = true
                transition(to: .processing(tool: nil))
            }
            return
        }

        // Tool permission request → waiting for user
        if line.contains("Emitted tool permission request") {
            let tool = extractToolName(from: line)
            Task { @MainActor in
                transition(to: .waitingForInput)
            }
            return
        }

        // Permission granted → processing that tool
        if line.contains("Received permission response") {
            let tool = extractToolName(from: line)
            Task { @MainActor in
                transition(to: .processing(tool: tool))
            }
            return
        }

        // Query completed → waiting for next input
        if line.contains("[Stop hook] Query completed") {
            Task { @MainActor in
                transition(to: .waitingForInput)
            }
            return
        }

        // Idle timeout → hide pill
        if line.contains("[IdleManager:session] Starting idle timeout") {
            Task { @MainActor in
                hasActiveSession = false
                transition(to: .idle)
            }
            return
        }

        // Error patterns
        if line.contains("[error]") && (line.contains("crashed") || line.contains("FATAL")) {
            let msg = String(line.suffix(80))
            Task { @MainActor in
                transition(to: .error(message: msg))
            }
            return
        }
    }

    /// Extract tool name from log lines like:
    /// "Emitted tool permission request ... for Bash in session ..."
    /// "Received permission response ... (tool: Bash)"
    private func extractToolName(from line: String) -> String? {
        // Pattern: "for ToolName in session"
        if let range = line.range(of: "for "),
           let endRange = line.range(of: " in session") {
            let start = range.upperBound
            let end = endRange.lowerBound
            if start < end {
                return String(line[start..<end])
            }
        }
        // Pattern: "(tool: ToolName)"
        if let range = line.range(of: "(tool: "),
           let endRange = line.range(of: ")", range: range.upperBound..<line.endIndex) {
            let start = range.upperBound
            let end = endRange.lowerBound
            return String(line[start..<end])
        }
        return nil
    }

    // MARK: - State Transition

    private func transition(to newState: ClaudeState) {
        guard newState != state else { return }
        state = newState
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeNotch/ClaudeStateMonitor.swift
git commit -m "feat: add ClaudeStateMonitor with log tailing and process detection"
```

---

### Task 4: NotchPillView — SwiftUI Animated Pill

**Files:**
- Create: `ClaudeNotch/NotchPillView.swift`

**Step 1: Implement the pill view**

The pill grows out of the black notch. When idle, it's invisible. When active, it shows a label with icon, coloured border glow, and breathing pulse for processing state.

```swift
import SwiftUI

struct NotchPillView: View {
    @ObservedObject var monitor: ClaudeStateMonitor
    @State private var pulse = false
    @State private var shakeOffset: CGFloat = 0

    private var pillContent: (label: String, icon: String, color: Color)? {
        switch monitor.state {
        case .idle:
            return nil
        case .launching:
            return ("Claude starting...", "arrow.clockwise", .indigo)
        case .processing(let tool):
            let label = tool.map { "Running \($0)" } ?? "Thinking..."
            return (label, "waveform", .purple)
        case .waitingForInput:
            return ("Waiting for you", "return", Color(red: 0.18, green: 0.75, blue: 0.65))
        case .error:
            return ("Claude stopped", "exclamationmark.triangle.fill", .orange)
        }
    }

    var body: some View {
        ZStack {
            if let content = pillContent {
                HStack(spacing: 6) {
                    Image(systemName: content.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .scaleEffect(pulse ? 1.18 : 1.0)
                        .foregroundStyle(content.color)

                    Text(content.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(Color.black)
                        .overlay {
                            Capsule()
                                .strokeBorder(content.color.opacity(0.5), lineWidth: 1)
                        }
                        .shadow(color: content.color.opacity(0.6),
                                radius: pulse ? 12 : 6, x: 0, y: 4)
                }
                .offset(x: shakeOffset)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity),
                    removal:   .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: monitor.state)
        .onChange(of: monitor.state) { _, newState in
            stopPulse()
            shakeOffset = 0
            if case .processing = newState { startPulse() }
            if case .error = newState { shakeAnimation() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private func stopPulse() {
        withAnimation(.easeOut(duration: 0.2)) { pulse = false }
    }

    private func shakeAnimation() {
        let sequence: [(CGFloat, Double)] = [
            (8, 0.05), (-6, 0.05), (4, 0.05), (-2, 0.05), (0, 0.05)
        ]
        var delay = 0.0
        for (offset, duration) in sequence {
            delay += duration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) {
                    shakeOffset = offset
                }
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeNotch/NotchPillView.swift
git commit -m "feat: add NotchPillView with animations"
```

---

### Task 5: NotchWindowController — NSWindow in the Notch

**Files:**
- Create: `ClaudeNotch/NotchWindowController.swift`

**Step 1: Implement the window controller**

Key compatibility concern: detect whether the current screen has a notch using `NSScreen.auxiliaryTopLeftArea` (available macOS 14+). If there's a notch, position the window to overlay it. Otherwise, float at top-centre.

The notch on:
- 14" MBP (2021+): ~162pt wide, ~37pt tall
- 16" MBP (2021+): ~162pt wide, ~37pt tall

We use a wider window (220pt) so the pill text fits, and position it centred at the very top of the screen.

```swift
import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!
    private let monitor: ClaudeStateMonitor

    init(monitor: ClaudeStateMonitor) {
        self.monitor = monitor
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let pillWidth: CGFloat = 220
        let pillHeight: CGFloat = 37
        let frame = windowFrame(for: screen, width: pillWidth, height: pillHeight)

        window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false

        let pillView = NotchPillView(monitor: monitor)
        window.contentView = NSHostingView(rootView: pillView)
        window.orderFrontRegardless()
    }

    func repositionForCurrentScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = windowFrame(for: screen, width: 220, height: 37)
        window.setFrame(frame, display: true)
    }

    private func windowFrame(for screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let x = screen.frame.midX - width / 2
        // Place at the very top of the screen frame
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Whether the given screen likely has a notch
    /// Uses auxiliaryTopLeftArea which is non-nil on notched displays (macOS 14+)
    static func screenHasNotch(_ screen: NSScreen) -> Bool {
        // auxiliaryTopLeftArea is non-nil when there's a notch
        return screen.auxiliaryTopLeftArea != nil
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeNotch/NotchWindowController.swift
git commit -m "feat: add NotchWindowController with notch detection"
```

---

### Task 6: MenuBarController

**Files:**
- Create: `ClaudeNotch/MenuBarController.swift`

**Step 1: Implement menu bar status item**

```swift
import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem!

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles",
                                           accessibilityDescription: "ClaudeNotch")

        let menu = NSMenu()
        menu.addItem(withTitle: "ClaudeNotch", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func update(for state: ClaudeState) {
        let symbolName: String
        switch state {
        case .idle:            symbolName = "sparkles"
        case .launching:       symbolName = "arrow.clockwise"
        case .processing:      symbolName = "waveform"
        case .waitingForInput: symbolName = "return"
        case .error:           symbolName = "exclamationmark.triangle"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName,
                                           accessibilityDescription: "Claude state")
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeNotch/MenuBarController.swift
git commit -m "feat: add MenuBarController"
```

---

### Task 7: App Entry Point — Wire Everything Together

**Files:**
- Modify: `ClaudeNotch/ClaudeNotchApp.swift`

**Step 1: Implement AppDelegate that wires monitor, window, and menu bar**

```swift
import SwiftUI
import AppKit
import Combine

@main
struct ClaudeNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = ClaudeStateMonitor()
    private let menuBar = MenuBarController()
    private var notchCtrl: NotchWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.setup()
        notchCtrl = NotchWindowController(monitor: monitor)

        monitor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.menuBar.update(for: state)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        monitor.startMonitoring()
    }

    @objc private func screenChanged() {
        notchCtrl.repositionForCurrentScreen()
    }
}
```

**Step 2: Commit**

```bash
git add ClaudeNotch/ClaudeNotchApp.swift
git commit -m "feat: wire app entry point with monitor, window, and menu bar"
```

---

### Task 8: Build & Test

**Step 1: Build the project**

```bash
xcodebuild -project ClaudeNotch.xcodeproj -scheme ClaudeNotch -configuration Debug build
```

Or open in Xcode and hit Cmd+R.

**Step 2: Verify checklist**

- [ ] App launches with no Dock icon
- [ ] Menu bar sparkle icon appears
- [ ] Open Claude Code → pill appears with "Claude starting..."
- [ ] Send a prompt → pill pulses purple "Thinking..."
- [ ] Tool permission prompt → pill shows "Waiting for you"
- [ ] Approve tool → pill shows "Running Bash"
- [ ] Query complete → pill shows "Waiting for you"
- [ ] Session idle → pill disappears
- [ ] Close Claude.app → pill disappears

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: ClaudeNotch v1.0 — complete build"
```
