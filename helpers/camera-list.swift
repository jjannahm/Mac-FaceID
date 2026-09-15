// camera-list — enumerate video capture devices, one per line:
//     <index>\t<kind>\t<name>
// where <kind> is "builtin", "continuity" or "external".
//
// Why this exists: OpenCV opens a camera by index, and on a Mac paired with an iPhone
// macOS happily makes the iPhone the first device. Unlocking sudo would then wake the
// phone instead of using the webcam sitting right there. The daemon uses this listing to
// pick the built-in camera unless the user asked for a specific one.
//
// The discovery session mirrors what OpenCV's AVFoundation backend enumerates, so the
// indices printed here match the ones VideoCapture expects.
import AVFoundation
import Foundation

// OpenCV's AVFoundation backend still indexes `devices(for:)`. A DiscoverySession may
// return a different order (notably with Continuity Camera), causing an index selected
// as "built-in" here to open the iPhone in OpenCV.
let devices = AVCaptureDevice.devices(for: .video)

for (index, device) in devices.enumerated() {
    var kind = "external"
    if device.deviceType == .builtInWideAngleCamera {
        kind = "builtin"
    } else if #available(macOS 14.0, *), device.deviceType == .continuityCamera {
        kind = "continuity"
    } else if device.modelID.contains("iPhone") || device.modelID.contains("iPad") {
        // Older systems surface Continuity cameras as plain external devices.
        kind = "continuity"
    }
    print("\(index)\t\(kind)\t\(device.localizedName)")
}
