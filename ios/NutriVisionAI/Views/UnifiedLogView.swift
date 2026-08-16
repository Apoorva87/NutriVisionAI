import SwiftUI

enum LogEntryMode: String, CaseIterable {
    case scan = "Scan"
    case search = "Search"
    case askAI = "Ask AI"

    var icon: String {
        switch self {
        case .scan:   return "camera.fill"
        case .search: return "magnifyingglass"
        case .askAI:  return "sparkles"
        }
    }
}

struct UnifiedLogView: View {
    @StateObject private var draftStore = MealDraftStore.shared

    // Default to Scan; the EntryPointBar at the top makes Search and Ask AI
    // a single tap away.
    @State private var activeMode: LogEntryMode = .scan
    @State private var showDraftReview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode selector: pill bar
                EntryPointBar(selection: $activeMode)

                // Content
                switch activeMode {
                case .scan:
                    ScanFlowView()
                case .search:
                    SearchFlowView()
                case .askAI:
                    AILookupFlowView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !draftStore.isEmpty {
                    MealDraftBar(onExpand: { showDraftReview = true })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: draftStore.isEmpty)
            .sheet(isPresented: $showDraftReview) {
                MealDraftReviewSheet()
                    .environmentObject(draftStore)
            }
        }
        .environmentObject(draftStore)
    }
}

// MARK: - Entry Point Bar

struct EntryPointBar: View {
    @Binding var selection: LogEntryMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LogEntryMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.caption)
                        Text(mode.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selection == mode ? Theme.accent.opacity(0.15) : Color.clear)
                    .foregroundStyle(selection == mode ? Theme.accent : Theme.textMuted)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(selection == mode ? Theme.accent.opacity(0.3) : Theme.cardBorder, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
