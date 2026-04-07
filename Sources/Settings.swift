import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "soundsEnabled") }
    }

    @Published var showProjectName: Bool {
        didSet { UserDefaults.standard.set(showProjectName, forKey: "showProjectName") }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            "soundsEnabled": true,
            "showProjectName": true
        ])
        self.soundsEnabled = UserDefaults.standard.bool(forKey: "soundsEnabled")
        self.showProjectName = UserDefaults.standard.bool(forKey: "showProjectName")
    }
}
