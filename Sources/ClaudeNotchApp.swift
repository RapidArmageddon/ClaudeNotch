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
