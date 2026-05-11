import AVFoundation
import SwiftUI

// NSObject subclass for the delegate; nonisolated so the capture queue callback
// isn't forced onto the main actor by SWIFT_DEFAULT_ACTOR_ISOLATION.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    // Called on the capture serial queue with each new frame
    nonisolated(unsafe) var onFrame: (@Sendable (CVPixelBuffer) -> Void)?

    let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "handwaiving.capture", qos: .userInteractive)
    private var currentDevice: AVCaptureDevice?

    // All cameras available for selection
    static func availableCameras() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices
    }

    func start(device: AVCaptureDevice? = nil) {
        let camera = device
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? CameraCapture.availableCameras().first
        guard let camera else { return }
        configure(device: camera)
    }

    func switchCamera(to device: AVCaptureDevice) {
        guard device != currentDevice else { return }
        session.stopRunning()
        session.inputs.forEach { session.removeInput($0) }
        configure(device: device)
    }

    func stop() {
        session.stopRunning()
    }

    // MARK: - Private

    private func configure(device: AVCaptureDevice) {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        currentDevice = device

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

// SwiftUI wrapper for a live camera preview layer
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
