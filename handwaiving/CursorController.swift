import CoreGraphics
import AppKit

@MainActor
@Observable
final class CursorController {
    private(set) var screenPosition: CGPoint = .zero

    // Exponential moving average weight — lower = more smoothing, higher = more responsive
    var smoothingAlpha: Double = 0.25

    private var smoothed: CGPoint = .zero
    private var cursorHidden = false

    func update(landmarks: HandLandmarks, transform: AffineTransform2D) {
        guard landmarks.isPointingPose else {
            unhideCursor()
            return
        }
        let raw = transform.apply(landmarks.indexTip)
        smoothed = CGPoint(
            x: smoothed.x + smoothingAlpha * (raw.x - smoothed.x),
            y: smoothed.y + smoothingAlpha * (raw.y - smoothed.y)
        )
        let clamped = clampToScreen(smoothed)
        screenPosition = clamped
        CGWarpMouseCursorPosition(appkitToCG(clamped))
        hideCursor()
    }

    func handLost() {
        unhideCursor()
    }

    // MARK: - Private

    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return p }
        let r = screen.frame
        return CGPoint(
            x: min(max(p.x, r.minX), r.maxX),
            y: min(max(p.y, r.minY), r.maxY)
        )
    }

    // CalibrationManager.screenPoint uses AppKit coords (y-up); CGWarpMouseCursorPosition
    // and CGEvent both use CG global display coords (y-down). Convert before posting.
    private func appkitToCG(_ p: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return p }
        return CGPoint(x: p.x, y: screen.frame.height - p.y)
    }

    private func hideCursor() {
        guard !cursorHidden else { return }
        NSCursor.hide()
        cursorHidden = true
    }

    private func unhideCursor() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }
}
