import XCTest
@testable import FaceKeyKit

final class FaceKeyKitTests: XCTestCase {
    func testRequestUsesVersionOneAndBoundedExpiry() throws {
        let before = Date().timeIntervalSince1970
        let request = FaceKeyAuthorizationRequest(action: "checkout", reason: "Approve order",
                                                  timeout: 999, bundleID: "com.jjannahm.FaceKey.Demo")
        XCTAssertEqual(request.version, 1)
        XCTAssertEqual(request.bundleID, "com.jjannahm.FaceKey.Demo")
        XCTAssertGreaterThan(request.expiresAt, before)
        XCTAssertLessThanOrEqual(request.expiresAt, before + 121)
        XCTAssertGreaterThanOrEqual(request.nonce.count, 16)
    }

    func testUnavailableWithoutRunningService() async throws {
        let request = FaceKeyAuthorizationRequest(action: "checkout", reason: "Approve order",
                                                  bundleID: "com.jjannahm.FaceKey.Demo")
        let result = try await FaceKeyClient.shared.authorize(request)
        XCTAssertEqual(result, .unavailable)
    }
}
