import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            AnalyzeView()
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }
                .tag(1)

            LogView()
                .tabItem {
                    Label("Log", systemImage: "plus.circle.fill")
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
}

// MARK: - Placeholder views

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            Text("Dashboard — coming soon")
                .navigationTitle("NutriVision")
        }
    }
}

struct AnalyzeView: View {
    var body: some View {
        NavigationStack {
            Text("Scan a meal photo — coming soon")
                .navigationTitle("Scan")
        }
    }
}

struct LogView: View {
    var body: some View {
        NavigationStack {
            Text("Quick log — coming soon")
                .navigationTitle("Log")
        }
    }
}

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            Text("History — coming soon")
                .navigationTitle("History")
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings — coming soon")
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
}
