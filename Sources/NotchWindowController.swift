import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!
    private let monitor: ClaudeStateMonitor

    init(monitor: ClaudeStateMonitor) {
        self.monitor = monitor
        super.init()
        rebuildWindow()
    }

    /// Tear down and recreate the window for the current screen topology.
    func rebuildWindow() {
        window?.orderOut(nil)
        window = nil

        if let notchScreen = Self.notchedScreen(),
           let notchInfo = Self.notchInfo(for: notchScreen) {
            setupNotchWindow(notchInfo: notchInfo)
        } else if let screen = NSScreen.main {
            setupFloatingWindow(on: screen)
        }
    }

    private func setupNotchWindow(notchInfo: NotchGeometry) {
        // Scale extension width proportionally to notch width
        // 16" MBP notch is ~186pt, 14" is ~162pt, Airs vary
        let extensionWidth = round(notchInfo.width * 0.27)  // ~50pt on 186pt notch

        let windowX = notchInfo.leftEdge - extensionWidth
        let windowWidth = extensionWidth + notchInfo.width + extensionWidth
        let windowHeight = notchInfo.height + 18  // extra for shadow below
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

    // MARK: - Window Visibility

    func hideWindow() {
        window?.orderOut(nil)
    }

    func showWindow() {
        window?.orderFrontRegardless()
    }

    // MARK: - Screen Detection

    /// Find the built-in notched screen, regardless of which display is "main"
    static func notchedScreen() -> NSScreen? {
        return NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
    }

    struct NotchGeometry {
        let leftEdge: CGFloat   // absolute x of notch left edge (in global NS coords)
        let rightEdge: CGFloat  // absolute x of notch right edge
        let width: CGFloat      // notch width in points
        let height: CGFloat     // notch height in points
        let bottomY: CGFloat    // absolute y of notch bottom edge (in global NS coords)
    }

    static func notchInfo(for screen: NSScreen) -> NotchGeometry? {
        guard let auxLeft = screen.auxiliaryTopLeftArea else { return nil }

        // auxiliaryTopLeftArea is in screen-local coordinates.
        // Add screen.frame.origin to get global NS coordinates for multi-monitor setups.
        let screenOriginX = screen.frame.origin.x
        let screenOriginY = screen.frame.origin.y

        let leftEdge = screenOriginX + auxLeft.maxX

        // Try to get the right auxiliary area for exact measurement.
        // If unavailable, mirror from the left (assumes symmetric layout).
        let rightEdge: CGFloat
        let rightSel = NSSelectorFromString("auxiliaryTopRightArea")
        if screen.responds(to: rightSel),
           let result = screen.perform(rightSel)?.takeUnretainedValue() as? NSValue {
            let rightArea = result.rectValue
            rightEdge = screenOriginX + rightArea.origin.x
        } else {
            // Fallback: assume symmetric
            rightEdge = screenOriginX + screen.frame.width - auxLeft.width
        }

        let notchWidth = rightEdge - leftEdge
        guard notchWidth > 0 else { return nil }

        return NotchGeometry(
            leftEdge: leftEdge,
            rightEdge: rightEdge,
            width: notchWidth,
            height: auxLeft.height,
            bottomY: screenOriginY + auxLeft.origin.y
        )
    }
}
