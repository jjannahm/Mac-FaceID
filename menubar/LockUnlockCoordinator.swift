import AppKit
import ApplicationServices
import Combine

@_silgen_name("CGSessionCopyCurrentDictionary")
private func CGSessionCopyCurrentDictionary() -> CFDictionary?

final class LockUnlockCoordinator: ObservableObject {
    @Published private(set) var state: LockUnlockState = .disabled
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var passwordConfigured = LockPasswordStore.hasPassword

    private var locked = false
    private var displayAwake = true
    private var policy = LockUnlockPolicy()
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    var enabled: Bool {
        get { Settings.shared.lockUnlockEnabled }
        set {
            Settings.shared.lockUnlockEnabled = newValue
            refresh()
            if newValue { beginIfPossible() }
        }
    }

    func start() {
        locked = Self.sessionIsLocked
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                                  object: nil, queue: .main) { [weak self] _ in
            self?.didLock()
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                                  object: nil, queue: .main) { [weak self] _ in
            self?.didUnlock()
        })
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.displayAwake = false
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.displayAwake = true
            self?.beginIfPossible()
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            if Self.sessionIsLocked { self?.didLock() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            if !Self.sessionIsLocked { self?.didUnlock() }
        })
        refresh()
        beginIfPossible()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
        passwordConfigured = LockPasswordStore.hasPassword
        if !enabled { state = .disabled }
        else if !prerequisitesReady { state = .unavailable }
        else if !locked { state = .waiting }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    func savePassword(_ password: String) throws {
        try LockPasswordStore.save(password)
        refresh()
    }

    func deletePassword() {
        LockPasswordStore.delete()
        Settings.shared.lockUnlockEnabled = false
        generation += 1
        refresh()
    }

    private var prerequisitesReady: Bool {
        accessibilityTrusted && passwordConfigured && Status.enrolled
    }

    private func didLock() {
        locked = true
        policy.beginLockCycle()
        generation += 1
        beginIfPossible()
    }

    private func didUnlock() {
        locked = false
        policy.beginLockCycle()
        generation += 1
        state = enabled ? .unlocked : .disabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.locked else { return }
            self.state = self.enabled ? .waiting : .disabled
        }
    }

    private func beginIfPossible() {
        refresh()
        guard enabled, prerequisitesReady, locked, displayAwake,
              policy.canAttemptRecognition, state != .scanning else { return }
        state = .scanning
        generation += 1
        let attempt = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Run.faceid(["verify-lock"])
            DispatchQueue.main.async {
                guard attempt == self.generation, self.locked else { return }
                if result.code == 0 && result.out.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
                    self.state = .matched
                    self.submitPassword(attempt: attempt)
                } else {
                    self.state = self.policy.recordRecognitionFailure()
                    if self.state != .suspended {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                            guard attempt == self.generation else { return }
                            self.beginIfPossible()
                        }
                    }
                }
            }
        }
    }

    private func submitPassword(attempt: Int) {
        guard attempt == generation, locked, policy.claimPasswordSubmission() else { return }
        state = .submitting
        do {
            let password = try LockPasswordStore.load()
            try AccessibilityPasswordTyper.submit(password)
            // Never retry a submitted credential during the same lock cycle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard self.locked, attempt == self.generation else { return }
                self.state = .suspended
            }
        } catch {
            state = .suspended
        }
    }

    private static var sessionIsLocked: Bool {
        guard let raw = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return raw["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

enum AccessibilityPasswordTyper {
    enum TypingError: Error { case denied, eventCreation }

    static func submit(_ password: String) throws {
        guard AXIsProcessTrusted() else { throw TypingError.denied }
        guard LockUnlockCoordinatorSessionGuard.isLocked else { throw TypingError.denied }

        // A harmless mouse movement wakes the lock surface without entering a character.
        if let wake = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: NSEvent.mouseLocation,
                              mouseButton: .left) {
            wake.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.75)
        guard LockUnlockCoordinatorSessionGuard.isLocked else { return }

        let units = Array(password.utf16)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false),
              let enterDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let enterUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
        else { throw TypingError.eventCreation }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        enterDown.post(tap: .cghidEventTap)
        enterUp.post(tap: .cghidEventTap)
    }
}

private enum LockUnlockCoordinatorSessionGuard {
    static var isLocked: Bool {
        guard let raw = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return raw["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
