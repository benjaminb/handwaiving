import AVFoundation
import AppKit

@MainActor
@Observable
final class AppModel {

    // MARK: - Sub-models (readable by views)
    let handDetector     = HandPoseDetector()
    let calibration      = CalibrationManager()
    let cursorController = CursorController()
    let gestureRecognizer = GestureRecognizer()
    let perfMonitor      = PerformanceMonitor()

    // MARK: - Services (not directly observed by views)
    let camera                = CameraCapture()
    private let desktop       = DesktopInteractor()
    private let overlay       = OverlayCursorWindow()
    private var playground:     PlaygroundWindowController?

    // MARK: - Published state for UI
    private(set) var availableCameras: [AVCaptureDevice] = []
    private(set) var selectedCamera: AVCaptureDevice?
    private(set) var isRunning = false
    private(set) var accessibilityGranted = false

    // Gesture → action mapping (configurable)
    var gestureMap: [GestureEvent: DesktopAction] = [
        .comeHere1: .click,
        .comeHere2: .doubleClick,
        .bang:      .rightClick
    ]

    init() {
        availableCameras = CameraCapture.availableCameras()
        selectedCamera = availableCameras.first

        // Wire gesture recognizer → desktop
        gestureRecognizer.onGesture = { [weak self] event in
            guard let self else { return }
            guard let action = self.gestureMap[event] else { return }
            self.desktop.perform(action, at: self.cursorController.screenPosition)
        }

        // Wire performance latency notifications
        NotificationCenter.default.addObserver(
            forName: .gestureLatencyRecorded,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let ms = note.userInfo?["ms"] as? Double {
                self?.perfMonitor.recordGestureLatency(ms: ms)
            }
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        checkAccessibility()

        camera.onFrame = { [weak self] pixelBuffer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.perfMonitor.recordFrame()
                self.handDetector.processFrame(pixelBuffer)
            }
        }

        handDetector.onLandmarks = { [weak self] landmarks in
            guard let self else { return }
            self.perfMonitor.recordInference(ms: self.handDetector.inferenceTimeMs)

            if let lm = landmarks {
                // Feed calibration if in progress
                self.calibration.feedLandmarks(lm)

                // Move cursor if calibrated
                if let transform = self.calibration.transform {
                    self.cursorController.update(landmarks: lm, transform: transform)
                    self.overlay.updateCursor(at: self.cursorController.screenPosition)
                    self.overlay.showHand()
                }

                // Feed gesture recognizer
                self.gestureRecognizer.feed(lm)
            } else {
                self.cursorController.handLost()
                self.overlay.showNoHand()
            }
        }

        camera.start(device: selectedCamera)
        overlay.show()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        camera.stop()
        overlay.hide()
        isRunning = false
    }

    func switchCamera(to device: AVCaptureDevice) {
        selectedCamera = device
        if isRunning {
            camera.switchCamera(to: device)
        }
    }

    func openPlayground() {
        if playground == nil {
            playground = PlaygroundWindowController()
        }
        playground?.show()
    }

    // MARK: - Accessibility

    func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }
}
