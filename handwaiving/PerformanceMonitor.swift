import Foundation

@MainActor
@Observable
final class PerformanceMonitor {
    private(set) var cameraFPS: Double = 0
    private(set) var inferenceTimeMs: Double = 0
    private(set) var gestureLatencyMs: Double = 0

    // Rolling window size for averages
    private let windowSize = 30

    private var frameTimestamps: [TimeInterval] = []
    private var inferenceSamples: [Double] = []
    private var latencySamples: [Double] = []

    var summary: String {
        String(format: "%.0f fps  /  %.0f ms inference  /  %.0f ms gesture", cameraFPS, inferenceTimeMs, gestureLatencyMs)
    }

    func recordFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        frameTimestamps.append(now)
        if frameTimestamps.count > windowSize {
            frameTimestamps.removeFirst()
        }
        if frameTimestamps.count >= 2 {
            let elapsed = frameTimestamps.last! - frameTimestamps.first!
            cameraFPS = elapsed > 0 ? Double(frameTimestamps.count - 1) / elapsed : 0
        }
    }

    func recordInference(ms: Double) {
        inferenceSamples.append(ms)
        if inferenceSamples.count > windowSize { inferenceSamples.removeFirst() }
        inferenceTimeMs = inferenceSamples.reduce(0, +) / Double(inferenceSamples.count)
    }

    func recordGestureLatency(ms: Double) {
        latencySamples.append(ms)
        if latencySamples.count > windowSize { latencySamples.removeFirst() }
        gestureLatencyMs = latencySamples.reduce(0, +) / Double(latencySamples.count)
    }
}
