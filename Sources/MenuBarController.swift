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
