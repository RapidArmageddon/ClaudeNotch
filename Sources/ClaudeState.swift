import Foundation

enum ClaudeState: Equatable {
    case idle
    case launching
    case processing(tool: String?)
    case waitingForInput
    case error(message: String)

    static func == (lhs: ClaudeState, rhs: ClaudeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.launching, .launching),
             (.waitingForInput, .waitingForInput):
            return true
        case let (.processing(a), .processing(b)):
            return a == b
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
