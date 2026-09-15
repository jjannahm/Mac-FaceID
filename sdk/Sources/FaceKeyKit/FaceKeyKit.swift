import Darwin
import Foundation

public struct FaceKeyAuthorizationRequest: Codable, Sendable {
    public let version: Int
    public let nonce: String
    public let bundleID: String
    public let action: String
    public let reason: String
    public let merchant: String?
    public let currency: String?
    public let amount: Decimal?
    public let expiresAt: TimeInterval

    public init(action: String, reason: String, merchant: String? = nil,
                currency: String? = nil, amount: Decimal? = nil,
                timeout: TimeInterval = 30,
                bundleID: String = Bundle.main.bundleIdentifier ?? "unknown") {
        self.version = 1
        self.nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        self.bundleID = bundleID
        self.action = action
        self.reason = reason
        self.merchant = merchant
        self.currency = currency
        self.amount = amount
        self.expiresAt = Date().timeIntervalSince1970 + min(max(timeout, 1), 120)
    }
}

public enum FaceKeyAuthorizationResult: String, Codable, Sendable {
    case approved, rejected, cancelled, unavailable, timedOut, fallbackRequired
}

public enum FaceKeyClientError: LocalizedError {
    case invalidRequest(String)
    public var errorDescription: String? {
        switch self { case .invalidRequest(let message): return message }
    }
}

public actor FaceKeyClient {
    public static let shared = FaceKeyClient()
    private var requestInFlight = false

    public func authorize(_ request: FaceKeyAuthorizationRequest) async throws
        -> FaceKeyAuthorizationResult {
        guard !requestInFlight else { throw FaceKeyClientError.invalidRequest("A request is already active") }
        guard !request.action.isEmpty, request.action.count <= 160,
              !request.reason.isEmpty, request.reason.count <= 160 else {
            throw FaceKeyClientError.invalidRequest("Action and reason must contain 1–160 characters")
        }
        requestInFlight = true
        defer { requestInFlight = false }
        return await Task.detached { Self.perform(request) }.value
    }

    private nonisolated static func perform(_ request: FaceKeyAuthorizationRequest)
        -> FaceKeyAuthorizationResult {
        let socketPath = NSHomeDirectory() + "/Library/Application Support/FaceKey/facekey.sock"
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .unavailable }
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: 125, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < pathCapacity else { return .unavailable }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self,
                                      capacity: pathCapacity) { destination in
                _ = socketPath.withCString { source in
                    strlcpy(destination, source, pathCapacity)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return .unavailable }
        guard let json = try? JSONEncoder().encode(request) else { return .fallbackRequired }
        let message = Data("AUTH ".utf8) + json + Data("\n".utf8)
        let sent = message.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard sent == message.count else { return .unavailable }
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return .timedOut }
        guard count > 0 else { return .unavailable }
        let response = String(decoding: buffer[..<count], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch response {
        case "APPROVED": return .approved
        case "REJECTED": return .rejected
        case "CANCELLED": return .cancelled
        case "ERR busy": return .fallbackRequired
        case "ERR expiry": return .timedOut
        case "ERR unavailable": return .unavailable
        case "ERR forbidden-client", "ERR replay", "ERR malformed", "ERR nonce", "ERR version":
            return .fallbackRequired
        default: return .unavailable
        }
    }
}
