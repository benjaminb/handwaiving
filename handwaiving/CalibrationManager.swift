import AppKit
import Foundation

// 2D affine transform — maps a direction vector to a screen coordinate.
// Computed from 3 non-collinear point pairs (TL, TR, BL corners).
struct AffineTransform2D: Codable {
    // x' = ax*x + bx*y + tx
    // y' = ay*x + by*y + ty
    let ax, bx, tx: Double
    let ay, by, ty: Double

    func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: ax * p.x + bx * p.y + tx,
            y: ay * p.x + by * p.y + ty
        )
    }

    // Solve from 3 source→destination point pairs using 3×3 matrix inversion
    static func from(
        src: (CGPoint, CGPoint, CGPoint),
        dst: (CGPoint, CGPoint, CGPoint)
    ) -> AffineTransform2D? {
        let (s0, s1, s2) = src
        let (d0, d1, d2) = dst
        // M * coeffs = rhs for x and y independently
        // M = [[s0.x, s0.y, 1], [s1.x, s1.y, 1], [s2.x, s2.y, 1]]
        let m: Mat3 = (
            (Double(s0.x), Double(s0.y), 1.0),
            (Double(s1.x), Double(s1.y), 1.0),
            (Double(s2.x), Double(s2.y), 1.0)
        )
        guard let inv = inverse3x3(m) else { return nil }
        let xRhs: (Double, Double, Double) = (Double(d0.x), Double(d1.x), Double(d2.x))
        let yRhs: (Double, Double, Double) = (Double(d0.y), Double(d1.y), Double(d2.y))
        let xC = matVec3(inv, xRhs)
        let yC = matVec3(inv, yRhs)
        return AffineTransform2D(
            ax: xC.0, bx: xC.1, tx: xC.2,
            ay: yC.0, by: yC.1, ty: yC.2
        )
    }
}

// 3×3 matrix stored as row triples
private typealias Mat3 = ((Double, Double, Double), (Double, Double, Double), (Double, Double, Double))

private func inverse3x3(_ m: Mat3) -> Mat3? {
    let (r0, r1, r2) = m
    let (a, b, c) = r0
    let (d, e, f) = r1
    let (g, h, i) = r2
    let det = a*(e*i - f*h) - b*(d*i - f*g) + c*(d*h - e*g)
    guard abs(det) > 1e-10 else { return nil }
    let inv = 1.0 / det
    return (
        ( (e*i - f*h)*inv,  (c*h - b*i)*inv,  (b*f - c*e)*inv ),
        ( (f*g - d*i)*inv,  (a*i - c*g)*inv,  (c*d - a*f)*inv ),
        ( (d*h - e*g)*inv,  (b*g - a*h)*inv,  (a*e - b*d)*inv )
    )
}

private func matVec3(_ m: Mat3, _ v: (Double, Double, Double)) -> (Double, Double, Double) {
    let (r0, r1, r2) = m
    return (
        r0.0*v.0 + r0.1*v.1 + r0.2*v.2,
        r1.0*v.0 + r1.1*v.1 + r1.2*v.2,
        r2.0*v.0 + r2.1*v.1 + r2.2*v.2
    )
}

enum CalibrationCorner: Int, CaseIterable {
    case topLeft, topRight, bottomRight, bottomLeft

    var label: String {
        switch self {
        case .topLeft:     return "Top-Left"
        case .topRight:    return "Top-Right"
        case .bottomRight: return "Bottom-Right"
        case .bottomLeft:  return "Bottom-Left"
        }
    }

    var screenPoint: CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let r = screen.frame
        let m: CGFloat = 40  // margin
        switch self {
        case .topLeft:     return CGPoint(x: r.minX + m, y: r.maxY - m)
        case .topRight:    return CGPoint(x: r.maxX - m, y: r.maxY - m)
        case .bottomRight: return CGPoint(x: r.maxX - m, y: r.minY + m)
        case .bottomLeft:  return CGPoint(x: r.minX + m, y: r.minY + m)
        }
    }
}

@MainActor
@Observable
final class CalibrationManager {
    enum State {
        case idle
        case collecting(CalibrationCorner, progress: Double)  // progress 0→1
        case calibrated
    }

    private(set) var state: State = .idle
    private(set) var transform: AffineTransform2D?

    private var collectedSamples: [CGPoint] = []
    private var cornerDirections: [CalibrationCorner: CGPoint] = [:]
    private var currentCornerIndex = 0
    private let samplesNeeded = 45  // ~1.5 s at 30fps

    private static let storageKey = "calibration_transform"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(AffineTransform2D.self, from: data) {
            transform = stored
            state = .calibrated
        }
    }

    func startCalibration() {
        cornerDirections.removeAll()
        currentCornerIndex = 0
        collectedSamples = []
        advanceToNextCorner()
    }

    // Feed each pointing-pose landmark into this during calibration
    func feedLandmarks(_ landmarks: HandLandmarks) {
        guard case .collecting(let corner, _) = state, landmarks.isPointingPose else { return }
        collectedSamples.append(landmarks.pointingDirection)
        let progress = Double(collectedSamples.count) / Double(samplesNeeded)
        state = .collecting(corner, progress: min(progress, 1.0))
        if collectedSamples.count >= samplesNeeded {
            finaliseCorner(corner)
        }
    }

    func reset() {
        cornerDirections.removeAll()
        transform = nil
        state = .idle
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Private

    private func advanceToNextCorner() {
        let corners = CalibrationCorner.allCases
        guard currentCornerIndex < corners.count else {
            computeTransform()
            return
        }
        collectedSamples = []
        state = .collecting(corners[currentCornerIndex], progress: 0)
    }

    private func finaliseCorner(_ corner: CalibrationCorner) {
        // Average of collected direction vectors
        let avgX = collectedSamples.map(\.x).reduce(0, +) / CGFloat(collectedSamples.count)
        let avgY = collectedSamples.map(\.y).reduce(0, +) / CGFloat(collectedSamples.count)
        cornerDirections[corner] = CGPoint(x: avgX, y: avgY)
        currentCornerIndex += 1
        advanceToNextCorner()
    }

    private func computeTransform() {
        guard
            let tl = cornerDirections[.topLeft],
            let tr = cornerDirections[.topRight],
            let bl = cornerDirections[.bottomLeft]
        else {
            state = .idle; return
        }
        let sTL = CalibrationCorner.topLeft.screenPoint
        let sTR = CalibrationCorner.topRight.screenPoint
        let sBL = CalibrationCorner.bottomLeft.screenPoint

        guard let t = AffineTransform2D.from(
            src: (tl, tr, bl),
            dst: (sTL, sTR, sBL)
        ) else { state = .idle; return }

        transform = t
        state = .calibrated
        if let data = try? JSONEncoder().encode(t) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
