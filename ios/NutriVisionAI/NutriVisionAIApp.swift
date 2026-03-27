import SwiftUI

@main
struct NutriVisionAIApp: App {
    init() {
        ContentView.configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
