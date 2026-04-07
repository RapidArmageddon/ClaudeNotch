import Foundation
import Combine
import AppKit

/// Handles file reading on a background queue, isolated from MainActor.
private final class LogFileReader: @unchecked Sendable {
    private var fileHandle: FileHandle?
    private var lastFileOffset: UInt64 = 0
    private let lock = NSLock()

    func open(path: String) -> Int32? {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let endOffset = handle.seekToEndOfFile()
        lock.lock()
        fileHandle = handle
        lastFileOffset = endOffset
        lock.unlock()
        return fd
    }

    /// Read recent lines from the end of the file to determine initial state
    func readRecentLines(count: Int = 100) -> [String] {
        lock.lock()
        guard let handle = fileHandle else {
            lock.unlock()
            return []
        }
        lock.unlock()

        // Read last ~8KB to find recent lines
        let endOffset = handle.seekToEndOfFile()
        let readSize: UInt64 = min(endOffset, 8192)
        let startOffset = endOffset - readSize
        handle.seek(toFileOffset: startOffset)
        let data = handle.readDataToEndOfFile()

        // Reset to end for future reads
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

    private var processTimer: Timer?
    private var logSource: DispatchSourceFileSystemObject?
    private let logReader = LogFileReader()
    private var claudeIsRunning = false
    private var hasActiveSession = false

    private let logPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/Claude/main.log"
    }()

    func startMonitoring() {
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

    private func pollForProcess() {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.anthropic.claude"
        }
        if isRunning && !claudeIsRunning {
            claudeIsRunning = true
        } else if !isRunning && claudeIsRunning {
            claudeIsRunning = false
            hasActiveSession = false
            transition(to: .idle)
        }
    }

    private func startLogWatcher() {
        guard FileManager.default.fileExists(atPath: logPath) else { return }
        guard let fd = logReader.open(path: logPath) else { return }

        // Read recent log lines to determine current state on launch
        let recentLines = logReader.readRecentLines(count: 50)
        for line in recentLines {
            parseLogLine(line)
        }

        let reader = logReader
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
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
    }

    private func stopLogWatcher() {
        logSource?.cancel()
        logSource = nil
        logReader.close()
    }

    private func parseLogLine(_ line: String) {
        if line.contains("LocalSessions.start") {
            hasActiveSession = true
            transition(to: .launching)
            return
        }
        if line.contains("LocalSessions.sendMessage") {
            hasActiveSession = true
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
        if line.contains("[IdleManager:session] Starting idle timeout") {
            hasActiveSession = false
            transition(to: .idle)
            return
        }
        if line.contains("[error]") && (line.contains("crashed") || line.contains("FATAL")) {
            let msg = String(line.suffix(80))
            transition(to: .error(message: msg))
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

    private func transition(to newState: ClaudeState) {
        guard newState != state else { return }
        NSLog("[ClaudeNotch] State: \(state) -> \(newState)")
        state = newState
    }
}
