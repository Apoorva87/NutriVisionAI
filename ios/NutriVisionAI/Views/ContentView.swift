import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Int

    init() {
        _selectedTab = State(initialValue: Self.initialTabSelection())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            UnifiedLogView()
                .tabItem {
                    Label("Log", systemImage: "plus.circle.fill")
                }
                .tag(1)

            GroceryListView()
                .tabItem {
                    Label("Grocery", systemImage: "cart.fill")
                }
                .tag(2)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.bar.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
    }

    static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.accent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.accent)]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.textMuted)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.textMuted)]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func initialTabSelection() -> Int {
        let env = ProcessInfo.processInfo.environment["NUTRIVISION_INITIAL_TAB"]
        guard let env, let tab = Int(env), (0...4).contains(tab) else { return 0 }
        return tab
    }
}

#Preview {
    ContentView()
}
