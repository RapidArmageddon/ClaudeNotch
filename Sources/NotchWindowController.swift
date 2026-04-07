import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!
    private let monitor: ClaudeStateMonitor
    private let extensionWidth: CGFloat = 50

    init(monitor: ClaudeStateMonitor) {
        self.monitor = monitor
        super.init()
        rebuildWindow()
    }

    /// Tear down and recreate the window for the current screen topology.
    /// Handles switching between notched and non-notched displays.
    func rebuildWindow() {
        window?.orderOut(nil)
        window = nil

        // Prefer the built-in notch screen over NSScreen.main
        if let notchScreen = Self.notchedScreen(),
           let notchInfo = Self.notchInfo(for: notchScreen) {
            setupNotchWindow(notchInfo: notchInfo)
        } else if let screen = NSScreen.main {
            setupFloatingWindow(on: screen)
        }
    }

    private func setupNotchWindow(notchInfo: NotchGeometry) {
        let windowX = notchInfo.leftEdge - extensionWidth
        let windowWidth = extensionWidth + notchInfo.width + extensionWidth
        let windowHeight: CGFloat = notchInfo.height + 18
        let windowY = notchInfo.bottomY - 18

        let frame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        window = makeWindow(frame: frame)

        let pillView = NotchPillView(
            monitor: monitor,
            notchWidth: notchInfo.width,
            leftExtensionWidth: extensionWidth,
            rightExtensionWidth: extensionWidth,
            notchHeight: notchInfo.height
        )
        window.contentView = NSHostingView(rootView: pillView)
        window.orderFrontRegardless()
    }

    private func setupFloatingWindow(on screen: NSScreen) {
        let width: CGFloat = 280
        let height: CGFloat = 36
        let x = screen.frame.midX - width / 2
        let y = screen.visibleFrame.maxY - height - 4
        let frame = NSRect(x: x, y: y, width: width, height: height)

        window = makeWindow(frame: frame)

        let pillView = NotchPillView(
            monitor: monitor,
            notchWidth: 0,
            leftExtensionWidth: 0,
            rightExtensionWidth: 0,
            notchHeight: height
        )
        window.contentView = NSHostingView(rootView: pillView)
        window.orderFrontRegardless()
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let w = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.isMovableByWindowBackground = false
        return w
    }

    // MARK: - Screen Detection

    /// Find the built-in notched screen, regardless of which display is "main"
    static func notchedScreen() -> NSScreen? {
        return NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
    }

    struct NotchGeometry {
        let leftEdge: CGFloat
        let width: CGFloat
        let height: CGFloat
        let bottomY: CGFloat
    }

    /// Hide window from compositor — zero GPU cost while idle
    func hideWindow() {
        window?.orderOut(nil)
    }

    /// Show window again
    func showWindow() {
        window?.orderFrontRegardless()
    }

    static func notchInfo(for screen: NSScreen) -> NotchGeometry? {
        guard let auxLeft = screen.auxiliaryTopLeftArea else { return nil }
        let leftEdge = auxLeft.maxX
        let rightEdge = screen.frame.width - auxLeft.width
        return NotchGeometry(
            leftEdge: leftEdge,
            width: rightEdge - leftEdge,
            height: auxLeft.height,
            bottomY: auxLeft.origin.y
        )
    }
}
