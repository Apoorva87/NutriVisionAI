import SwiftUI

struct NetworkLogsView: View {
    @State private var logs: [NetworkLogEntry] = []

    var body: some View {
        List {
            if logs.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.textMuted)
                        Text("No network calls logged yet")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Text("Use the app to scan food or generate meal plans")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(logs) { entry in
                    NetworkLogRow(entry: entry)
                        .listRowBackground(Theme.cardSurface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Network Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    NetworkLogger.shared.clearAll()
                    logs = []
                }
                .foregroundStyle(Theme.destructive)
                .disabled(logs.isEmpty)
            }
        }
        .onAppear { logs = NetworkLogger.shared.recentLogs() }
    }
}

// MARK: - Log Row

private struct NetworkLogRow: View {
    let entry: NetworkLogEntry

    private var providerColor: Color {
        switch entry.provider {
        case "gemini": return .blue
        case "openai": return .green
        case "openrouter": return .purple
        default: return .gray
        }
    }

    private var providerIcon: String {
        switch entry.provider {
        case "gemini": return "sparkles"
        case "openai": return "brain"
        case "openrouter": return "arrow.triangle.branch"
        default: return "server.rack"
        }
    }

    private var timeString: String {
        // Parse ISO8601 and show HH:mm:ss
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: entry.timestamp) else {
            return String(entry.timestamp.suffix(8))
        }
        let display = DateFormatter()
        display.dateFormat = "HH:mm:ss"
        display.timeZone = AppTimeZone.current
        return display.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(entry.status == "ok" ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                // Provider
                Image(systemName: providerIcon)
                    .font(.caption2)
                    .foregroundStyle(providerColor)
                Text(entry.provider)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(providerColor)

                // Action
                Text(entry.action)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                Spacer()

                // Duration badge
                Text("\(entry.durationMs)ms")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(durationColor.opacity(0.15))
                    .foregroundStyle(durationColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)

                if let size = entry.responseSizeBytes {
                    Text(formatBytes(size))
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            if let error = entry.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.destructive)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var durationColor: Color {
        if entry.durationMs < 1000 { return .green }
        if entry.durationMs < 3000 { return .orange }
        return .red
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        return "\(bytes / 1024) KB"
    }
}
