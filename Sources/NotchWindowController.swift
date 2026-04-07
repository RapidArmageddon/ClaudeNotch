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
        guard let notchInfo = Self.notchInfo(for: screen) else {
            // No notch — use a simple centered floating window
            setupFloatingWindow(on: screen)
            return
        }

        // The window spans from left extension through the notch gap to right extension.
        // We position it using absolute screen coordinates.
        let extensionWidth: CGFloat = 50  // width of each side panel
        let windowX = notchInfo.leftEdge - extensionWidth
        let windowWidth = extensionWidth + notchInfo.width + extensionWidth + 30  // +40 for right text
        let windowHeight: CGFloat = notchInfo.height + 18  // extra for shadow below

        // In NS coordinates: y is from bottom
        let windowY = notchInfo.bottomY - 18  // extend below for shadow

        let frame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)

        window = makeWindow(frame: frame)

        let pillView = NotchPillView(
            monitor: monitor,
            notchWidth: notchInfo.width,
            leftExtensionWidth: extensionWidth,
            rightExtensionWidth: extensionWidth + 30,
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

    func repositionForCurrentScreen() {
        guard let screen = NSScreen.main else { return }
        guard let notchInfo = Self.notchInfo(for: screen) else { return }

        let extensionWidth: CGFloat = 50
        let windowX = notchInfo.leftEdge - extensionWidth
        let windowWidth = extensionWidth + notchInfo.width + extensionWidth + 30
        let windowHeight: CGFloat = notchInfo.height + 18
        let windowY = notchInfo.bottomY - 18

        let frame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        window.setFrame(frame, display: true)
    }

    struct NotchGeometry {
        let leftEdge: CGFloat   // NS x-coordinate of notch left edge
        let width: CGFloat      // notch width in points
        let height: CGFloat     // notch height in points
        let bottomY: CGFloat    // NS y-coordinate of notch bottom edge
    }

    static func notchInfo(for screen: NSScreen) -> NotchGeometry? {
        guard let auxLeft = screen.auxiliaryTopLeftArea else { return nil }
        let leftEdge = auxLeft.maxX
        let rightEdge = screen.frame.width - auxLeft.width  // symmetric
        return NotchGeometry(
            leftEdge: leftEdge,
            width: rightEdge - leftEdge,
            height: auxLeft.height,
            bottomY: auxLeft.origin.y
        )
    }
}
