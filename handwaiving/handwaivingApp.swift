import SwiftUI
import AVFoundation

@main
struct handwaivingApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 400, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
