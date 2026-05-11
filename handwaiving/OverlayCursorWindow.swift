import AppKit
import CoreGraphics

// Full-screen transparent window drawn above all other windows.
// Renders a visible custom cursor and snaps to nearby interactive UI elements.
final class OverlayCursorWindow {

    private var window: NSWindow?
    private var cursorView: CursorView?
    private var isVisible = false

    func show() {
        guard window == nil, let screen = NSScreen.main else { return }
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = CursorView(frame: screen.frame)
        win.contentView = view
        win.orderFrontRegardless()

        self.window = win
        self.cursorView = view
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        cursorView = nil
        isVisible = false
    }

    // Called on every frame when a hand is detected
    func updateCursor(at point: CGPoint) {
        guard isVisible else { return }
        let snapped = snap(point) ?? point
        cursorView?.cursorPosition = snapped
        cursorView?.isSnapped = snapped != point
        cursorView?.needsDisplay = true
    }

    func showNoHand() {
        cursorView?.handVisible = false
        cursorView?.needsDisplay = true
    }

    func showHand() {
        cursorView?.handVisible = true
        cursorView?.needsDisplay = true
    }

    // MARK: - Sticky snap via Accessibility API

    // Returns the snapped position if a snap target is within 24 pts, nil otherwise
    private func snap(_ point: CGPoint) -> CGPoint? {
        let axPoint = screenToAXCoords(point)
        let element = AXUIElementCreateSystemWide()
        var ref: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(element, Float(axPoint.x), Float(axPoint.y), &ref)
        guard result == .success, let el = ref else { return nil }

        // Check sub-role for window control buttons
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = subroleValue as? String ?? ""
        let isSnapTarget = [kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole].contains(subrole)
            || isMenuBarItem(el)
        guard isSnapTarget else { return nil }

        // Get element frame and return its centre
        var frameValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &frameValue)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeValue)
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let fv = frameValue { AXValueGetValue(fv as! AXValue, .cgPoint, &origin) }
        if let sv = sizeValue  { AXValueGetValue(sv as! AXValue, .cgSize, &size)   }
        let centre = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let axCentre = axToScreenCoords(centre)
        guard hypot(axCentre.x - point.x, axCentre.y - point.y) < 24 else { return nil }
        return axCentre
    }

    private func isMenuBarItem(_ el: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleValue)
        return (roleValue as? String) == kAXMenuBarItemRole
    }

    // AX uses top-left origin; NSScreen uses bottom-left
    private func screenToAXCoords(_ p: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return p }
        return CGPoint(x: p.x, y: screen.frame.height - p.y)
    }

    private func axToScreenCoords(_ p: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return p }
        return CGPoint(x: p.x, y: screen.frame.height - p.y)
    }
}

// MARK: - Cursor view

private final class CursorView: NSView {
    var cursorPosition: CGPoint = .zero
    var isSnapped = false
    var handVisible = false

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard handVisible else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let p = cursorPosition
        let radius: CGFloat = isSnapped ? 14 : 10

        // Outer ring
        ctx.setStrokeColor((isSnapped ? NSColor.systemYellow : NSColor.white).cgColor)
        ctx.setLineWidth(isSnapped ? 3 : 2.5)
        ctx.strokeEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2))

        // Inner dot
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))

        // Cross-hair ticks
        let tick: CGFloat = 6
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeLineSegments(between: [
            CGPoint(x: p.x - radius - tick, y: p.y), CGPoint(x: p.x - radius + 1, y: p.y),
            CGPoint(x: p.x + radius - 1, y: p.y),    CGPoint(x: p.x + radius + tick, y: p.y),
            CGPoint(x: p.x, y: p.y - radius - tick),  CGPoint(x: p.x, y: p.y - radius + 1),
            CGPoint(x: p.x, y: p.y + radius - 1),     CGPoint(x: p.x, y: p.y + radius + tick)
        ])
    }
}
