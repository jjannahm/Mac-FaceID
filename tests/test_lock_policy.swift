import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@main
struct PolicyTests {
    static func main() {
        var policy = LockUnlockPolicy()
        require(policy.canAttemptRecognition, "new cycle accepts recognition")
        require(policy.recordRecognitionFailure() == .failed, "first failure retries")
        require(policy.recordRecognitionFailure() == .failed, "second failure retries")
        require(policy.recordRecognitionFailure() == .suspended, "third failure suspends")
        require(!policy.canAttemptRecognition, "suspended cycle cannot scan")
        policy.beginLockCycle()
        require(policy.claimPasswordSubmission(), "first password submission is accepted")
        require(!policy.claimPasswordSubmission(), "second password submission is rejected")
        require(!policy.canAttemptRecognition, "submitted cycle cannot scan again")
        policy.beginLockCycle()
        require(policy.canAttemptRecognition, "manual unlock resets the policy")
        print("LockUnlockPolicy tests passed")
    }
}
