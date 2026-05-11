import Foundation

enum GestureEvent {
    case comeHere1   // single index curl → click
    case comeHere2   // double index curl → double-click
    case bang        // thumb dip + raise → right-click
}

// Default mapping from gesture to desktop action
extension GestureEvent {
    var defaultAction: DesktopAction {
        switch self {
        case .comeHere1: return .click
        case .comeHere2: return .doubleClick
        case .bang:      return .rightClick
        }
    }
}

@MainActor
@Observable
final class GestureRecognizer {
    var onGesture: ((GestureEvent) -> Void)?

    // Gesture latency tracking: set when a gesture starts forming
    var gestureStartTime: TimeInterval?

    // MARK: - Come-here state

    private enum ComeHereState {
        case idle
        case curlDetected(at: TimeInterval, count: Int)  // mid-curl
        case waitingForRepeat(count: Int, deadline: TimeInterval)  // between curls
    }

    private var comeHereState: ComeHereState = .idle
    // Baseline index extension captured when entering pointing pose
    private var baselineIndexExtension: CGFloat = 0

    // MARK: - Bang state

    private enum BangState {
        case idle
        case thumbDown(startedAt: TimeInterval)
    }

    private var bangState: BangState = .idle

    // MARK: - Feed

    func feed(_ landmarks: HandLandmarks) {
        updateBaselineIfNeeded(landmarks)
        processComeHere(landmarks)
        processBang(landmarks)
    }

    // MARK: - Come-here (index finger curl)

    private func updateBaselineIfNeeded(_ lm: HandLandmarks) {
        // Capture baseline index length when hand is clearly in pointing pose
        if lm.isPointingPose && baselineIndexExtension < lm.handScale * 0.3 {
            baselineIndexExtension = lm.indexExtension
        }
    }

    private func processComeHere(_ lm: HandLandmarks) {
        guard baselineIndexExtension > 0.01 else { return }
        let now = lm.timestamp
        let curled = lm.indexExtension < baselineIndexExtension * 0.55  // 45% reduction = curl

        switch comeHereState {
        case .idle:
            if curled {
                gestureStartTime = now
                comeHereState = .curlDetected(at: now, count: 1)
            }

        case .curlDetected(let startedAt, let count):
            if !curled {
                // Finger returned — wait briefly to see if another curl follows
                comeHereState = .waitingForRepeat(count: count, deadline: now + 0.45)
            } else if now - startedAt > 0.8 {
                // Held too long, reset
                comeHereState = .idle
            }

        case .waitingForRepeat(let count, let deadline):
            if curled {
                // Another curl started
                comeHereState = .curlDetected(at: now, count: count + 1)
            } else if now > deadline {
                // Window expired — fire with current count
                fireGesture(count == 1 ? .comeHere1 : .comeHere2)
                comeHereState = .idle
            }
        }
    }

    // MARK: - Bang (thumb dip then raise)

    private func processBang(_ lm: HandLandmarks) {
        guard lm.isPointingPose else {
            bangState = .idle; return
        }
        let now = lm.timestamp
        // Vision y=0 at bottom. "Thumb down" = thumbTip.y < wrist.y by a threshold
        let thumbDown = lm.thumbHeightRelativeToWrist < -lm.handScale * 0.6

        switch bangState {
        case .idle:
            if thumbDown {
                gestureStartTime = now
                bangState = .thumbDown(startedAt: now)
            }

        case .thumbDown(let startedAt):
            if !thumbDown {
                // Thumb came back up
                let elapsed = now - startedAt
                if elapsed < 0.7 {
                    // Snappy motion — fire
                    fireGesture(.bang)
                }
                bangState = .idle
            } else if now - startedAt > 1.0 {
                // Held too long, not a bang
                bangState = .idle
            }
        }
    }

    // MARK: - Helpers

    private func fireGesture(_ event: GestureEvent) {
        if let start = gestureStartTime {
            let latencyMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
            NotificationCenter.default.post(
                name: .gestureLatencyRecorded,
                object: nil,
                userInfo: ["ms": latencyMs]
            )
        }
        gestureStartTime = nil
        onGesture?(event)
    }
}

extension Notification.Name {
    static let gestureLatencyRecorded = Notification.Name("gestureLatencyRecorded")
}
