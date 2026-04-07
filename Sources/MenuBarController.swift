import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem!
    private var soundsItem: NSMenuItem!
    private var showProjectNameItem: NSMenuItem!

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles",
                                           accessibilityDescription: "ClaudeNotch")

        let menu = NSMenu()
        menu.addItem(withTitle: "ClaudeNotch", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        soundsItem = NSMenuItem(title: "Sounds",
                                action: #selector(toggleSounds),
                                keyEquivalent: "")
        soundsItem.target = self
        soundsItem.state = Settings.shared.soundsEnabled ? .on : .off
        menu.addItem(soundsItem)

        showProjectNameItem = NSMenuItem(title: "Show Project Name",
                                        action: #selector(toggleShowProjectName),
                                        keyEquivalent: "")
        showProjectNameItem.target = self
        showProjectNameItem.state = Settings.shared.showProjectName ? .on : .off
        menu.addItem(showProjectNameItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleSounds() {
        Settings.shared.soundsEnabled.toggle()
        soundsItem.state = Settings.shared.soundsEnabled ? .on : .off
    }

    @objc private func toggleShowProjectName() {
        Settings.shared.showProjectName.toggle()
        showProjectNameItem.state = Settings.shared.showProjectName ? .on : .off
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
