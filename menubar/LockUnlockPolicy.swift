import Foundation

enum LockUnlockState: String {
    case disabled, waiting, scanning, matched, submitting, unlocked, failed, suspended, unavailable

    var label: String {
        switch self {
        case .disabled: return "Disabled"
        case .waiting: return "Ready — waiting for the Mac to lock"
        case .scanning: return "Scanning with the MacBook camera"
        case .matched: return "Face matched"
        case .submitting: return "Submitting the saved password"
        case .unlocked: return "Unlocked"
        case .failed: return "Recognition failed; waiting to retry"
        case .suspended: return "Suspended until you unlock manually"
        case .unavailable: return "Setup or permission unavailable"
        }
    }
}

struct LockUnlockPolicy {
    private(set) var failures = 0
    private(set) var submitted = false

    mutating func beginLockCycle() {
        failures = 0
        submitted = false
    }

    mutating func recordRecognitionFailure() -> LockUnlockState {
        failures += 1
        return failures >= 3 ? .suspended : .failed
    }

    mutating func claimPasswordSubmission() -> Bool {
        guard !submitted else { return false }
        submitted = true
        return true
    }

    var canAttemptRecognition: Bool { failures < 3 && !submitted }
}
