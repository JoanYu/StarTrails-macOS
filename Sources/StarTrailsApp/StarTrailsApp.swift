import SwiftUI

@main
struct StarTrailsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            // Optional: Add menu commands here
        }
    }
}
