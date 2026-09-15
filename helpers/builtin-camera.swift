import AVFoundation
import CoreImage
import Foundation

// Emits length-prefixed JPEG frames from the Mac's physical built-in camera.
// Continuity/external cameras are excluded by the discovery device type itself.
final class FrameWriter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var lastFrame = DispatchTime.now().uptimeNanoseconds

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastFrame >= 100_000_000,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let image = CIImage(cvPixelBuffer: buffer)
        guard let jpeg = context.jpegRepresentation(of: image,
                                                     colorSpace: colorSpace,
                                                     options: [:]) else { return }
        var length = UInt32(jpeg.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(jpeg)
    }
}

let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
).devices
guard let camera = devices.first else {
    FileHandle.standardError.write(Data("No built-in camera found\n".utf8))
    exit(2)
}

let session = AVCaptureSession()
session.beginConfiguration()
session.sessionPreset = .vga640x480
do {
    session.addInput(try AVCaptureDeviceInput(device: camera))
} catch {
    FileHandle.standardError.write(Data("Built-in camera unavailable: \(error)\n".utf8))
    exit(3)
}
let output = AVCaptureVideoDataOutput()
output.alwaysDiscardsLateVideoFrames = true
output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA]
let writer = FrameWriter()
let queue = DispatchQueue(label: "com.jjannahm.FaceKey.builtin-camera")
output.setSampleBufferDelegate(writer, queue: queue)
guard session.canAddOutput(output) else { exit(4) }
session.addOutput(output)
session.commitConfiguration()
session.startRunning()
RunLoop.main.run()
