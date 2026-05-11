import AppKit
import SwiftUI

final class PlaygroundWindowController: NSWindowController {

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Gesture Playground"
        win.center()
        win.contentView = NSHostingView(rootView: PlaygroundView())
        self.init(window: win)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI content

private struct PlaygroundView: View {
    @State private var clickCount = 0
    @State private var doubleClickCount = 0
    @State private var rightClickCount = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var textInput = ""
    @State private var sliderValue: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("Gesture Playground")
                .font(.title2.bold())

            Divider()

            // Click targets
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

            // Text field
            HStack {
                Text("Type here:")
                TextField("Try clicking to focus, then type…", text: $textInput)
                    .textFieldStyle(.roundedBorder)
            }

            // Slider
            HStack {
                Text("Slider:")
                Slider(value: $sliderValue)
                Text(String(format: "%.2f", sliderValue))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            Divider()

            // Scrollable list
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
            .frame(maxHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 400)
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

#Preview {
    PlaygroundView()
        .frame(width: 560, height: 480)
}
