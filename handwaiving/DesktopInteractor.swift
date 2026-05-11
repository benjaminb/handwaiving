import CoreGraphics
import Foundation

enum DesktopAction {
    case click
    case doubleClick
    case rightClick
}

final class DesktopInteractor {

    func perform(_ action: DesktopAction, at position: CGPoint) {
        switch action {
        case .click:
            post(.leftMouseDown, at: position)
            post(.leftMouseUp, at: position)
        case .doubleClick:
            post(.leftMouseDown, at: position, clickCount: 1)
            post(.leftMouseUp, at: position, clickCount: 1)
            post(.leftMouseDown, at: position, clickCount: 2)
            post(.leftMouseUp, at: position, clickCount: 2)
        case .rightClick:
            post(.rightMouseDown, at: position)
            post(.rightMouseUp, at: position)
        }
    }

    // MARK: - Private

    private func post(_ type: CGEventType, at position: CGPoint, clickCount: Int64 = 1) {
        let button: CGMouseButton = (type == .rightMouseDown || type == .rightMouseUp) ? .right : .left
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return }
        if clickCount > 1 {
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        }
        event.post(tap: .cghidEventTap)
    }
}
