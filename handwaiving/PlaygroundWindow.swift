import AppKit
import SwiftUI

final class PlaygroundWindowController: NSWindowController {

    convenience init(model: AppModel) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Gesture Playground"
        win.contentView = NSHostingView(rootView: PlaygroundView().environment(model))
        self.init(window: win)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI content

private struct PlaygroundView: View {
    @Environment(AppModel.self) private var model
    @State private var clickCount = 0
    @State private var doubleClickCount = 0
    @State private var rightClickCount = 0
    @State private var textInput = ""
    @State private var sliderValue: Double = 0.5

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: interactive targets
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Gesture Playground")
                        .font(.title2.bold())

                    Divider()

                    HStack(spacing: 12) {
                        countButton("Click me", count: clickCount, color: .accentColor) {
                            clickCount += 1
                        }
                        countButton("Double-click", count: doubleClickCount, color: .green) {
                            doubleClickCount += 1
                        }
                        contextMenuButton(count: rightClickCount) {
                            rightClickCount += 1
                        }
                    }

                    Divider()

                    HStack {
                        Text("Type here:")
                        TextField("Try clicking to focus, then type…", text: $textInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Slider:")
                        Slider(value: $sliderValue)
                        Text(String(format: "%.2f", sliderValue))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }

                    Divider()

                    Text("Scrollable list (try come-here 1x on items):")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(1..<25) { i in
                                HStack {
                                    Text("List item \(i)")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(i.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

                    Spacer()
                }
                .padding(20)
            }
            .frame(minWidth: 460)

            Divider()

            // Right: hand debug panel
            HandDebugPanel(
                landmarks: model.handDetector.latestLandmarks,
                screenPos: model.cursorController.screenPosition
            )
            .frame(width: 300)
            .padding(16)
        }
        .frame(minWidth: 780, minHeight: 500)
    }

    @ViewBuilder
    private func countButton(_ label: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                Text("\(count)")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(color)
            }
            .frame(width: 120, height: 56)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func contextMenuButton(count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Right-click me")
                Text("\(count)")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.orange)
            }
            .frame(width: 120, height: 56)
        }
        .buttonStyle(.bordered)
        .contextMenu {
            Button("Option A") { action() }
            Button("Option B") { action() }
            Divider()
            Button("Reset count") { }
        }
    }
}

// MARK: - Hand debug panel

private struct HandDebugPanel: View {
    let landmarks: HandLandmarks?
    let screenPos: CGPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hand Debug")
                .font(.headline)

            HandSketchView(landmarks: landmarks)
                .frame(height: 160)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let lm = landmarks {
                let pipDist    = lm.indexExtension
                let scale      = lm.handScale
                let pipRatio   = scale > 0 ? pipDist / scale : 0
                let midTipDist = hypot(lm.middleTip.x - lm.wrist.x, lm.middleTip.y - lm.wrist.y)
                let midMCPDist = hypot(lm.middleMCP.x - lm.wrist.x, lm.middleMCP.y - lm.wrist.y)
                let midRatio   = midMCPDist > 0 ? midTipDist / midMCPDist : 0

                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    debugRow("Index extended", flag: lm.isIndexExtended)
                    debugRow("Pointing pose",  flag: lm.isPointingPose)
                    debugRow("PIP→wrist",   value: String(format: "%.4f", pipDist))
                    debugRow("Hand scale",  value: String(format: "%.4f", scale))
                    debugRow("PIP/scale",   value: String(format: "%.3f", pipRatio),
                             note: pipRatio >= 1.1 ? nil : "needs > 1.1")
                    debugRow("Mid tip→wrist", value: String(format: "%.4f", midTipDist))
                    debugRow("Mid MCP→wrist", value: String(format: "%.4f", midMCPDist))
                    debugRow("Mid ratio",   value: String(format: "%.3f", midRatio),
                             note: midRatio < 1.3 ? nil : "needs < 1.3")
                    debugRow("Index tip",
                             value: String(format: "(%.3f, %.3f)",
                                           lm.indexTip.x, lm.indexTip.y))
                    debugRow("Screen pos",
                             value: String(format: "(%.0f, %.0f)", screenPos.x, screenPos.y))
                }
                .textSelection(.enabled)
            } else {
                Text("No hand detected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func debugRow(_ label: String, flag: Bool) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Circle()
                    .fill(flag ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(flag ? "yes" : "no")
                    .font(.caption.monospaced())
            }
        }
    }

    @ViewBuilder
    private func debugRow(_ label: String, value: String, note: String? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value)
                    .font(.caption.monospaced())
                if let note {
                    Text("← \(note)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Hand skeleton canvas

private struct HandSketchView: View {
    let landmarks: HandLandmarks?

    var body: some View {
        Canvas { ctx, size in
            guard let lm = landmarks else {
                // Placeholder text
                var text = AttributedString("No hand")
                text.font = .systemFont(ofSize: 13)
                text.foregroundColor = .secondaryLabelColor
                ctx.draw(Text(text), at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }

            func pt(_ p: CGPoint) -> CGPoint {
                // Vision: (0,0)=bottom-left, (1,1)=top-right → flip y, add margin
                let margin: CGFloat = 12
                let w = size.width  - margin * 2
                let h = size.height - margin * 2
                return CGPoint(x: margin + p.x * w,
                               y: margin + (1 - p.y) * h)
            }

            // Skeleton segments: (from, to, isIndex)
            let segments: [(CGPoint, CGPoint, Bool)] = [
                (lm.wrist, lm.indexMCP,  false),
                (lm.indexMCP, lm.indexPIP, true),
                (lm.indexPIP, lm.indexTip, true),
                (lm.wrist, lm.middleMCP, false),
                (lm.middleMCP, lm.middleTip, false),
                (lm.wrist, lm.ringTip,   false),
                (lm.wrist, lm.littleTip, false),
                (lm.wrist, lm.thumbTip,  false),
            ]

            for (a, b, isIndex) in segments {
                var path = Path()
                path.move(to: pt(a))
                path.addLine(to: pt(b))
                ctx.stroke(path,
                           with: .color(isIndex ? .blue : .gray),
                           lineWidth: isIndex ? 2 : 1.5)
            }

            // Joints
            let joints: [(CGPoint, Bool)] = [
                (lm.wrist, false), (lm.thumbTip, false),
                (lm.indexMCP, true), (lm.indexPIP, true), (lm.indexTip, true),
                (lm.middleMCP, false), (lm.middleTip, false),
                (lm.ringTip, false), (lm.littleTip, false),
            ]
            for (p, isIndex) in joints {
                let r: CGFloat = isIndex ? 4 : 3
                let rect = CGRect(x: pt(p).x - r, y: pt(p).y - r, width: r*2, height: r*2)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color(isIndex ? .blue : Color.primary.opacity(0.6)))
            }
        }
    }
}

#Preview {
    PlaygroundView()
        .environment(AppModel())
        .frame(width: 900, height: 700)
}
