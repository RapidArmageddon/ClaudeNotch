import Foundation
import Combine
import AppKit

/// Handles file reading on a background queue, isolated from MainActor.
private final class LogFileReader: @unchecked Sendable {
    private var fileHandle: FileHandle?
    private var lastFileOffset: UInt64 = 0
    private var openedInode: UInt64 = 0
    private let lock = NSLock()

    func open(path: String) -> Int32? {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return nil }

        var st = Darwin.stat()
        fstat(fd, &st)

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let endOffset = handle.seekToEndOfFile()
        lock.lock()
        fileHandle = handle
        lastFileOffset = endOffset
        openedInode = UInt64(st.st_ino)
        lock.unlock()
        return fd
    }

    func readRecentLines(count: Int = 100) -> [String] {
        lock.lock()
        guard let handle = fileHandle else {
            lock.unlock()
            return []
        }
        lock.unlock()

        let endOffset = handle.seekToEndOfFile()
        let readSize: UInt64 = min(endOffset, 8192)
        let startOffset = endOffset - readSize
        handle.seek(toFileOffset: startOffset)
        let data = handle.readDataToEndOfFile()

        let finalOffset = handle.seekToEndOfFile()
        lock.lock()
        lastFileOffset = finalOffset
        lock.unlock()

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return Array(lines.suffix(count))
    }

    func readNewLines() -> [String] {
        lock.lock()
        guard let handle = fileHandle else {
            lock.unlock()
            return []
        }
        let offset = lastFileOffset
        lock.unlock()

        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        let newOffset = handle.offsetInFile

        lock.lock()
        lastFileOffset = newOffset
        lock.unlock()

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    func close() {
        lock.lock()
        fileHandle = nil
        lock.unlock()
    }
}

@MainActor
final class ClaudeStateMonitor: ObservableObject {
    @Published private(set) var state: ClaudeState = .idle

    private var logSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var logReader = LogFileReader()
    private var claudeIsRunning = false
    private var hasActiveSession = false
    private var launchingTimeout: DispatchWorkItem?

    /// Discovers the Claude Desktop log path.
    /// Checks standard location: ~/Library/Logs/Claude/main.log
    private let logPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Library/Logs/Claude/main.log",
        ]
        // Return the first path that exists, or the primary candidate as default
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? candidates[0]
    }()

    private var logDirPath: String {
        (logPath as NSString).deletingLastPathComponent
    }

    func startMonitoring() {
        // Event-driven process detection instead of polling
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(appDidLaunch(_:)),
                         name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(appDidTerminate(_:)),
                         name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Check if Claude is already running at startup
        claudeIsRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.anthropic.claude"
        }

        startLogWatcherOrWaitForFile()
    }

    func stopMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopLogWatcher()
        stopDirWatcher()
        cancelLaunchingTimeout()
    }

    // MARK: - Process Detection (event-driven)

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.anthropic.claude" else { return }
        claudeIsRunning = true
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.anthropic.claude" else { return }
        claudeIsRunning = false
        hasActiveSession = false
        cancelLaunchingTimeout()
        transition(to: .idle)
    }

    // MARK: - Launching Timeout

    private func startLaunchingTimeout() {
        cancelLaunchingTimeout()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, case .launching = self.state else { return }
                self.transition(to: .idle)
            }
        }
        launchingTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    private func cancelLaunchingTimeout() {
        launchingTimeout?.cancel()
        launchingTimeout = nil
    }

    // MARK: - Log Watching

    private func startLogWatcherOrWaitForFile() {
        if FileManager.default.fileExists(atPath: logPath) {
            startLogWatcher()
        } else {
            watchDirectoryForFileCreation()
        }
    }

    private func startLogWatcher() {
        stopLogWatcher()
        logReader = LogFileReader()

        guard let fd = logReader.open(path: logPath) else { return }

        // Read recent log lines to determine current state
        let recentLines = logReader.readRecentLines(count: 50)
        for line in recentLines {
            parseLogLine(line)
        }

        let reader = logReader
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            // .delete and .rename detect log rotation — no polling timer needed
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }

            // Check if file was rotated (deleted/renamed and recreated)
            let event = source.data
            if event.contains(.delete) || event.contains(.rename) {
                Task { @MainActor in
                    self.startLogWatcher()
                }
                return
            }

            let lines = reader.readNewLines()
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                for line in lines {
                    self?.parseLogLine(line)
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        logSource = source

        stopDirWatcher()
    }

    private func stopLogWatcher() {
        logSource?.cancel()
        logSource = nil
        logReader.close()
    }

    private func watchDirectoryForFileCreation() {
        let dirPath = logDirPath
        try? FileManager.default.createDirectory(
            atPath: dirPath, withIntermediateDirectories: true)

        let fd = Darwin.open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .link],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if FileManager.default.fileExists(atPath: self.logPath) {
                    self.startLogWatcher()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    private func stopDirWatcher() {
        dirSource?.cancel()
        dirSource = nil
    }

    // MARK: - Log Parsing

    private func parseLogLine(_ line: String) {
        if line.contains("LocalSessions.start") ||
           line.contains("LocalAgentModeSessions.start") {
            hasActiveSession = true
            startLaunchingTimeout()
            transition(to: .launching)
            return
        }

        if line.contains("LocalSessions.sendMessage") {
            hasActiveSession = true
            cancelLaunchingTimeout()
            transition(to: .processing(tool: nil))
            return
        }

        if line.contains("Emitted tool permission request") {
            transition(to: .waitingForInput)
            return
        }

        if line.contains("Received permission response") {
            let tool = extractToolName(from: line)
            transition(to: .processing(tool: tool))
            return
        }

        if line.contains("[Stop hook] Query completed") {
            transition(to: .waitingForInput)
            return
        }

        // Note: [IdleManager:session] fires constantly between tool calls
        // (it just means "start a 900s countdown"). Not a real idle signal.
        // The pill only hides when Claude.app terminates (process watcher).

        if line.contains("[CCD CycleHealth] unhealthy cycle") {
            let reason = extractCycleHealthReason(from: line)
            let message: String
            switch reason {
            case "api_error":           message = "API error"
            case "no_response":         message = "No response"
            case "app_quit":            message = "App quit"
            case "cli_execution_error": message = "CLI error"
            default:                    message = reason ?? "Error"
            }
            transition(to: .error(message: message))
            return
        }
    }

    private func extractToolName(from line: String) -> String? {
        if let range = line.range(of: "for "),
           let endRange = line.range(of: " in session") {
            let start = range.upperBound
            let end = endRange.lowerBound
            if start < end { return String(line[start..<end]) }
        }
        if let range = line.range(of: "(tool: "),
           let endRange = line.range(of: ")", range: range.upperBound..<line.endIndex) {
            return String(line[range.upperBound..<endRange.lowerBound])
        }
        return nil
    }

    private func extractCycleHealthReason(from line: String) -> String? {
        guard let range = line.range(of: "reason=") else { return nil }
        let after = line[range.upperBound...]
        let end = after.firstIndex(of: ")") ?? after.endIndex
        let reason = String(after[after.startIndex..<end])
        return reason.isEmpty ? nil : reason
    }

    // MARK: - State Transition

    private func transition(to newState: ClaudeState) {
        guard newState != state else { return }
        state = newState
    }
}
