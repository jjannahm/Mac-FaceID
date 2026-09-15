import SwiftUI

@main
struct FaceKeyCheckoutDemo: App {
    var body: some Scene { WindowGroup("FaceKey Checkout") { CheckoutView() } }
}

struct CheckoutView: View {
    @State private var state = "Ready"
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Example checkout").font(.largeTitle.bold())
                Text("This purchase is a local demonstration. It does not use Apple Pay or charge a card.")
                    .foregroundStyle(.secondary)
            }
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pro workspace").font(.headline)
                        Text("Demo merchant · One-time purchase").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("$24.00").font(.title2.monospacedDigit().bold())
                }.padding(8)
            }
            HStack {
                Label(state, systemImage: icon).foregroundStyle(color)
                Spacer()
                Button("Approve with FaceKey") { approve() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy)
            }
            Text("FaceKey uses your Mac's RGB camera. A photo or video may fool it; use this only for convenience-grade approvals.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28).frame(minWidth: 560, minHeight: 330)
    }

    private var icon: String {
        switch state { case "Approved": return "checkmark.circle.fill"
        case "Rejected", "Fallback required": return "xmark.circle.fill"
        default: return "info.circle" }
    }
    private var color: Color { state == "Approved" ? .green : (state == "Ready" ? .secondary : .orange) }

    private func approve() {
        busy = true; state = "Waiting for FaceKey…"
        Task {
            let request = FaceKeyAuthorizationRequest(
                action: "approve a demo purchase", reason: "Confirm the Pro workspace order",
                merchant: "FaceKey Demo Merchant", currency: "USD", amount: 24,
                bundleID: "com.jjannahm.FaceKey.Demo")
            do {
                let result = try await FaceKeyClient.shared.authorize(request)
                state = result.displayName
            } catch { state = "Fallback required" }
            busy = false
        }
    }
}

private extension FaceKeyAuthorizationResult {
    var displayName: String {
        switch self {
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .cancelled: return "Cancelled"
        case .unavailable: return "FaceKey unavailable"
        case .timedOut: return "Timed out"
        case .fallbackRequired: return "Fallback required"
        }
    }
}
