# Handwaiving

A macOS proof-of-concept that lets you control your desktop with hand gestures via a webcam. No external ML dependencies — built entirely on Apple's built-in Vision framework (`VNDetectHumanHandPoseRequest`).

---

## How it works

### Cursor positioning

The app uses a **fingertip-position calibration** approach (touchpad model):

1. Vision detects hand landmarks in each camera frame.
2. The **index fingertip position** (`indexTip`) in Vision's normalized [0, 1]² image coordinate space is used as the cursor signal.
3. A one-time **4-corner calibration** maps this image position to screen coordinates. The user extends their index finger toward each screen corner; the app averages ~45 frames of `indexTip` samples per corner, then solves a 2D affine transform (3×3 matrix inversion) that maps any fingertip position to a screen coordinate.
4. The calibration transform is applied on every frame, followed by **exponential moving average smoothing** (α=0.25) to reduce jitter.
5. `CGWarpMouseCursorPosition` moves the system cursor to the computed position.

The key insight: the fingertip's 2D image position is always well-defined regardless of which direction the finger is angled. Earlier direction-vector approaches collapsed under foreshortening when the finger pointed toward the camera (e.g. at the screen centre).

### Gesture recognition

Gestures are detected by state machines running on the landmark stream.

| Gesture | How it's detected | Default action |
|---|---|---|
| Pointing (index extended, middle curled) | `dist(indexPIP, wrist) > handScale * 1.1` AND `dist(middleTip, wrist) < dist(middleMCP, wrist) * 1.3` | Move cursor |
| **Come-here 1×** (single index curl) | PIP→wrist distance drops to <55% of pointing-pose baseline within 300ms, then returns | Click |
| **Come-here 2×** (double index curl) | Same curl detected twice within 450ms window | Double-click |
| **Bang** (thumb dip + raise while pointing) | `thumbTip.y < wrist.y - handScale*0.6`, then returns within 700ms | Right-click |

Using the PIP (middle knuckle) joint instead of the fingertip for extension detection makes the check robust to foreshortening — when the index finger points toward the camera its tip appears near the MCP in 2D, but the PIP remains laterally displaced from the wrist. Vision coordinates have y=0 at the bottom of the image.

The gesture → action mapping is stored as a `[GestureEvent: DesktopAction]` dictionary in `AppModel` and can be remapped at runtime.

### Overlay cursor

A borderless, always-on-top, click-through `NSWindow` draws a custom ring+crosshair cursor at the current position. The system cursor is hidden via `NSCursor.hide()` while the hand is visible.

**Sticky snap**: on each frame, `AXUIElementCopyElementAtPosition` queries the UI element under the cursor. If within 24pt of a window close/minimize/zoom button or menu bar item, the cursor snaps to that element's centre and the ring turns yellow.

---

## Architecture

```
handwaiving/
├── handwaivingApp.swift       App entry, injects AppModel into environment
├── AppModel.swift             @Observable coordinator — owns all services, wires the pipeline
├── ContentView.swift          Main UI: camera picker, calibration flow, perf HUD, controls
│
├── CameraCapture.swift        AVCaptureSession wrapper; enumerates cameras; hot-swaps
├── HandPoseDetector.swift     VNDetectHumanHandPoseRequest on a background VisionActor
├── CalibrationManager.swift   4-corner calibration → AffineTransform2D; persists to UserDefaults
├── CursorController.swift     Applies transform + EMA smoothing; calls CGWarpMouseCursorPosition
├── GestureRecognizer.swift    State machines: bang (right-click), come-here 1×/2× (click/double-click)
├── DesktopInteractor.swift    Posts CGEvents for click, double-click, right-click
├── OverlayCursorWindow.swift  Transparent full-screen NSWindow; custom cursor; sticky snap via AX
├── PerformanceMonitor.swift   Rolling 30-frame averages: camera FPS, inference ms, gesture latency
└── PlaygroundWindow.swift     Demo window with buttons, context menu, text field, slider, list
```

### Data flow

```
Webcam (30fps)
  → CameraCapture (AVCaptureSession, background queue)
  → HandPoseDetector.processFrame()  [drops frame if previous not done]
  → VisionActor.process()            [background actor, ~10-20ms]
  → HandLandmarks                    [back on MainActor]
  → CalibrationManager.feedLandmarks()   [during calibration only]
  → CursorController.update()            [maps direction → screen, smooths, moves cursor]
  → OverlayCursorWindow.updateCursor()   [draws overlay]
  → GestureRecognizer.feed()             [state machines]
  → GestureEvent                         [bang / comeHere1 / comeHere2]
  → DesktopInteractor.perform()          [CGEvent post]
```

---

## Setup

### Requirements
- macOS 14+ (Sonoma or later)
- Xcode 16+
- A webcam (built-in or external USB)

### Permissions
Two permissions are required:

| Permission | Where to grant | Used for |
|---|---|---|
| **Camera** | System dialog on first launch | Capturing video frames |
| **Accessibility** | System Settings → Privacy & Security → Accessibility | Posting click events via CGEvent; sticky snap via AXUIElement |

The app sandbox entitlement `com.apple.security.device.camera` is already configured in `handwaiving.entitlements`.

### Running

Open `handwaiving.xcodeproj` in Xcode and press ⌘R, or:

```bash
open handwaiving.xcodeproj
```

### First-time workflow

1. Launch the app
2. Grant **Camera** permission when the dialog appears
3. Go to **System Settings → Privacy & Security → Accessibility** and enable Handwaiving
4. Press **Start** in the control panel
5. Press **Start Calibration** — point your index finger at each screen corner and hold for ~1.5 seconds each
6. After calibration, your pointing finger controls the cursor
7. Click **Open Playground** to try gesture interactions in the demo window

Calibration is saved to `UserDefaults` and survives restarts. Press **Recalibrate** any time you move the camera or change your seating position.

---

## Tuning

| Parameter | Location | Effect |
|---|---|---|
| `smoothingAlpha` | `CursorController` | Lower = smoother but laggier cursor (default 0.25) |
| Index extension threshold | `HandLandmarks.isPointingPose` — `scale * 1.1` | Raise if pointing activates too easily; lower if extended index is missed |
| Middle curl threshold | `HandLandmarks.isPointingPose` — `middleMCPDist * 1.3` | Raise if partially-curled middle still blocks pointing recognition |
| Bang thumb threshold | `GestureRecognizer.processBang` | `handScale * 0.6` — increase if accidental triggers |
| Come-here curl threshold | `GestureRecognizer.processComeHere` | `0.55` of baseline — decrease if curls go undetected |
| Calibration samples | `CalibrationManager.samplesNeeded` | More samples = more stable calibration (default 45) |
| Sticky snap radius | `OverlayCursorWindow.snap` | 24pt — increase for easier snapping |

---

## Known limitations (PoC)

- **Single hand only** — `maximumHandCount = 1`
- **Affine calibration** — works well for a stationary setup; a full projective homography would handle more extreme angles
- **No scroll gesture yet** — the architecture supports it (add a new `GestureEvent` case and wire it to a scroll `CGEvent`)
- **Single screen** — the overlay window targets `NSScreen.main`; multi-monitor support would require one overlay per screen
- **Accessibility must be manually enabled** — the system will not auto-grant it even if the user approved it previously after a code-sign change
