import AppKit

let args = CommandLine.arguments
func value(_ flag: String, fallback: String = "") -> String {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return fallback }
    return args[i + 1]
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.activate(ignoringOtherApps: true)

let alert = NSAlert()
alert.alertStyle = .informational
alert.messageText = "Approve with FaceKey?"
let caller = value("--caller", fallback: "An app")
let action = value("--action")
let reason = value("--reason")
let merchant = value("--merchant")
let amount = value("--amount")
var lines = ["\(caller) wants to \(action).", reason]
if !merchant.isEmpty { lines.append("Merchant: \(merchant)") }
if !amount.isEmpty { lines.append("Amount: \(amount)") }
lines.append("FaceKey uses a normal webcam and is convenience-grade, not Apple Face ID.")
alert.informativeText = lines.filter { !$0.isEmpty }.joined(separator: "\n\n")
alert.addButton(withTitle: "Continue")
alert.addButton(withTitle: "Cancel")
print(alert.runModal() == .alertFirstButtonReturn ? "APPROVE" : "CANCEL")
