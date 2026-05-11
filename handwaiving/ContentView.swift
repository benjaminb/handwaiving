import SwiftUI
import AVFoundation

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // Performance HUD — always visible at top
            HUDBar(monitor: model.perfMonitor)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cameraSection
                    controlSection
                    calibrationSection
                    statusSection
                }
                .padding()
            }
        }
        .frame(minWidth: 380, minHeight: 480)
    }

    // MARK: - Camera

    private var cameraSection: some View {
        GroupBox("Camera") {
            VStack(alignment: .leading, spacing: 10) {
                if model.availableCameras.isEmpty {
                    Text("No cameras found").foregroundStyle(.secondary)
                } else {
                    Picker("Source", selection: Binding(
                        get: { model.selectedCamera },
                        set: { if let cam = $0 { model.switchCamera(to: cam) } }
                    )) {
                        ForEach(model.availableCameras, id: \.uniqueID) { cam in
                            Text(cam.localizedName).tag(Optional(cam))
                        }
                    }

                    if model.isRunning {
                        CameraPreviewView(session: model.camera.session)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(model.handDetector.isHandVisible ? Color.green : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Control

    private var controlSection: some View {
        GroupBox("Control") {
            HStack(spacing: 12) {
                Button(model.isRunning ? "Stop" : "Start") {
                    if model.isRunning { model.stop() } else { model.start() }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRunning ? .red : .accentColor)

                Button("Open Playground") {
                    model.openPlayground()
                }
                .disabled(!model.isRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Calibration

    private var calibrationSection: some View {
        GroupBox("Calibration") {
            VStack(alignment: .leading, spacing: 10) {
                switch model.calibration.state {
                case .idle:
                    Button("Start Calibration") {
                        model.calibration.startCalibration()
                    }
                    .disabled(!model.isRunning)
                    Text("Point at each screen corner when prompted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .collecting(let corner, let progress):
                    Text("Point at: **\(corner.label)**")
                    ProgressView(value: progress)
                    Text("Hold still while pointing at the corner…")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .calibrated:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Calibrated")
                    }
                    Button("Recalibrate") {
                        model.calibration.reset()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    statusRow(
                        "Accessibility",
                        ok: model.accessibilityGranted,
                        hint: model.accessibilityGranted ? nil : "Grant in System Settings → Privacy → Accessibility, then toggle off/on after each rebuild"
                    )
                    Spacer()
                    if model.accessibilityGranted {
                        Button("Check") { model.checkAccessibility() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    } else {
                        Button("Request…") { model.requestAccessibilityPermission() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                statusRow(
                    "Hand detected",
                    ok: model.handDetector.isHandVisible
                )
                statusRow(
                    "Cursor active",
                    ok: model.isRunning && model.calibration.transform != nil
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusRow(_ label: String, ok: Bool, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ok ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(label)
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
            }
        }
    }
}

// MARK: - HUD

private struct HUDBar: View {
    let monitor: PerformanceMonitor

    var body: some View {
        Text(monitor.summary)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
