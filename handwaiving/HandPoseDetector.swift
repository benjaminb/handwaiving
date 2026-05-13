import Vision
import Foundation

// CVPixelBuffer is a CFTypeRef — mark Sendable so it can cross actor boundaries.
// Vision reads it without modification; we never write concurrently.
extension CVPixelBuffer: @unchecked @retroactive Sendable {}

struct HandLandmarks: Sendable {
    let wrist: CGPoint
    let thumbTip: CGPoint
    let indexMCP: CGPoint
    let indexPIP: CGPoint
    let indexTip: CGPoint
    let middleMCP: CGPoint
    let middleTip: CGPoint
    let ringTip: CGPoint
    let littleTip: CGPoint
    let timestamp: TimeInterval

    // Unit vector from index knuckle → fingertip in Vision image space
    var pointingDirection: CGPoint {
        let dx = indexTip.x - indexMCP.x
        let dy = indexTip.y - indexMCP.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return .zero }
        return CGPoint(x: dx / len, y: dy / len)
    }

    // Distance wrist→indexMCP used as a hand-size normaliser
    var handScale: CGFloat {
        hypot(indexMCP.x - wrist.x, indexMCP.y - wrist.y)
    }

    // True when index is clearly extended and middle is curled (pointing pose).
    // Uses wrist-relative distances instead of tip-to-MCP projected lengths, which
    // collapse under foreshortening when the finger points toward the camera.
    var isPointingPose: Bool {
        let scale = handScale
        guard scale > 0.01 else { return false }
        // PIP further from wrist than MCP → index is extended even when foreshortened
        let pipFromWrist = hypot(indexPIP.x - wrist.x, indexPIP.y - wrist.y)
        let indexExtended = pipFromWrist > scale * 1.1
        // Middle tip not substantially further from wrist than middle MCP → curled
        let middleTipFromWrist = hypot(middleTip.x - wrist.x, middleTip.y - wrist.y)
        let middleMCPFromWrist = hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y)
        let middleCurled = middleTipFromWrist < middleMCPFromWrist * 1.3
        return indexExtended && middleCurled
    }

    // Positive = thumb above wrist (Vision y increases upward)
    var thumbHeightRelativeToWrist: CGFloat {
        thumbTip.y - wrist.y
    }

    // PIP-to-wrist distance — robust to foreshortening, used for come-here curl detection
    var indexExtension: CGFloat {
        hypot(indexPIP.x - wrist.x, indexPIP.y - wrist.y)
    }

    // Looser check used during calibration — middle curl not required
    var isIndexExtended: Bool {
        indexExtension > handScale * 1.1
    }
}

// Runs VNDetectHumanHandPoseRequest on its own actor (background thread)
private actor VisionActor {
    private let request = VNDetectHumanHandPoseRequest()

    init() {
        request.maximumHandCount = 1
    }

    func process(_ pixelBuffer: CVPixelBuffer) -> (HandLandmarks?, Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return (nil, 0)
        }
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        guard let obs = request.results?.first else { return (nil, ms) }
        return (extractLandmarks(obs), ms)
    }

    private func extractLandmarks(_ obs: VNHumanHandPoseObservation) -> HandLandmarks? {
        guard
            let wrist     = try? obs.recognizedPoint(.wrist),     wrist.confidence     > 0.15,
            let thumbTip  = try? obs.recognizedPoint(.thumbTip),
            let indexMCP  = try? obs.recognizedPoint(.indexMCP),
            let indexPIP  = try? obs.recognizedPoint(.indexPIP),
            let indexTip  = try? obs.recognizedPoint(.indexTip),  indexTip.confidence  > 0.15,
            let middleMCP = try? obs.recognizedPoint(.middleMCP),
            let middleTip = try? obs.recognizedPoint(.middleTip),
            let ringTip   = try? obs.recognizedPoint(.ringTip),
            let littleTip = try? obs.recognizedPoint(.littleTip)
        else { return nil }

        return HandLandmarks(
            wrist:     wrist.location,
            thumbTip:  thumbTip.location,
            indexMCP:  indexMCP.location,
            indexPIP:  indexPIP.location,
            indexTip:  indexTip.location,
            middleMCP: middleMCP.location,
            middleTip: middleTip.location,
            ringTip:   ringTip.location,
            littleTip: littleTip.location,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }
}

@MainActor
@Observable
final class HandPoseDetector {
    private(set) var latestLandmarks: HandLandmarks?
    private(set) var inferenceTimeMs: Double = 0
    private(set) var isHandVisible = false

    private let vision = VisionActor()
    private var isProcessing = false

    var onLandmarks: ((HandLandmarks?) -> Void)?

    // Drop frame if Vision is still working on the previous one
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            let (landmarks, ms) = await vision.process(pixelBuffer)
            self.inferenceTimeMs = ms
            self.latestLandmarks = landmarks
            self.isHandVisible = landmarks != nil
            self.onLandmarks?(landmarks)
            self.isProcessing = false
        }
    }
}
