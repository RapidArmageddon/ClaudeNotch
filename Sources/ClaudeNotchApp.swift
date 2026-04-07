import SwiftUI
import AppKit
import Combine

@main
struct ClaudeNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}

@MainActor
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
                if state == .idle {
                    self?.notchCtrl.hideWindow()
                } else {
                    self?.notchCtrl.showWindow()
                }
                self?.playChime(for: state)
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
        notchCtrl.rebuildWindow()
    }

    private func playChime(for state: ClaudeState) {
        guard Settings.shared.soundsEnabled else { return }
        let soundName: String?
        switch state {
        case .waitingForInput:
            soundName = monitor.isPermissionRequest ? "Pop" : "Tink"
        case .error:
            soundName = "Basso"
        default:
            soundName = nil
        }
        if let name = soundName {
            NSSound(named: NSSound.Name(name))?.play()
        }
    }
}
