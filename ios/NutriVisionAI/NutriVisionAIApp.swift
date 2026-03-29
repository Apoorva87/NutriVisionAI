import SwiftUI

@main
struct NutriVisionAIApp: App {
    init() {
        ContentView.configureTabBarAppearance()
        Self.migrateKeychainAccessibility()
    }

    /// Re-save existing API keys with correct accessibility so they survive app restarts.
    private static func migrateKeychainAccessibility() {
        let keys = ["openai_api_key", "google_api_key", "openrouter_api_key", "anthropic_api_key"]
        for key in keys {
            if let value = KeychainHelper.read(key: key) {
                try? KeychainHelper.save(key: key, value: value)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
