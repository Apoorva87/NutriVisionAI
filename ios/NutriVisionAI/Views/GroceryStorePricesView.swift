// GroceryStorePricesView — iBuyGrocery "Today" screen inside NutriVisionAI.
// Pushed from GroceryListView after the user taps "Find Prices at Stores".
// Shows each cart line with its resolving / resolved recommended candidate, live via SSE.

import SwiftUI

struct GroceryStorePricesView: View {
    @State private var list: IBGShoppingList?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var selectedItem: IBGListItem?
    @StateObject private var sse = IBuyGrocerySSEClient()

    /// Raw grocery lines to push to iBuyGrocery backend on first appear.
    /// When non-empty, we call /lists/{id}/items with these and then clear it.
    let itemsToSeed: [String]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Group {
                if isLoading && list == nil {
                    ProgressView("Finding prices…")
                        .foregroundStyle(Theme.textSecondary)
                } else if let error = errorMessage, list == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.textMuted)
                        Text("Can't reach Store Prices backend")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal)
                        NavigationLink("Open Settings") {
                            IBuyGrocerySettingsView()
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        Button("Retry") { Task { await refresh() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else if let list = list {
                    content(list: list)
                }
            }
        }
        .navigationTitle("Store Prices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let list = list {
                    NavigationLink {
                        GroceryBasketPlanView(listId: list.id)
                    } label: {
                        Image(systemName: "cart")
                    }
                }
            }
        }
        .task { await firstLoad() }
        .refreshable { await refresh() }
        .sheet(item: $selectedItem) { item in
            GroceryCandidatesSheet(
                itemId: item.id,
                itemLabel: item.rawText,
                currentSelectionId: item.selectedCandidateId,
                onSelectionChanged: { updatedList in
                    list = updatedList
                }
            )
        }
    }

    @ViewBuilder
    private func content(list: IBGShoppingList) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = errorMessage {
                    errorBanner(error)
                        .padding(.horizontal)
                }

                if list.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cart")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.textMuted)
                        Text("No items yet")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Add items from your cart on the Grocery List page.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity)
                    .themedCard()
                    .padding()
                } else {
                    // SSE connection indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sse.isConnected ? Color.green : Theme.textMuted)
                            .frame(width: 7, height: 7)
                        Text(sse.isConnected ? "Live updates on" : "Offline — pull to refresh")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                        Button {
                            Task { try? await IBuyGroceryClient.shared.reResolveList(listId: list.id) }
                        } label: {
                            Label("Re-resolve all", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal)

                    ForEach(list.items) { item in
                        StorePriceRow(item: item, onTap: { selectedItem = item })
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.destructive)
            Text(error)
                .font(.caption)
                .foregroundStyle(Theme.destructive)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button("Retry") { Task { await refresh() } }
                .font(.caption)
                .buttonStyle(.bordered)
        }
        .padding(10)
        .themedCard()
    }

    // MARK: - Actions

    private func firstLoad() async {
        do {
            var current = try await IBuyGroceryClient.shared.getTodayList()
            if !itemsToSeed.isEmpty {
                let rawText = itemsToSeed.joined(separator: "\n")
                current = try await IBuyGroceryClient.shared.addItems(listId: current.id, rawText: rawText)
            }
            list = current
            errorMessage = nil
            isLoading = false
            connectSSE(listId: current.id)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func refresh() async {
        do {
            let current = try await IBuyGroceryClient.shared.getTodayList()
            list = current
            errorMessage = nil
            if !sse.isConnected {
                connectSSE(listId: current.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connectSSE(listId: Int) {
        sse.onItemResolved = { updatedItem in
            guard var current = list else { return }
            var items = current.items
            if let idx = items.firstIndex(where: { $0.id == updatedItem.id }) {
                items[idx] = updatedItem
            } else {
                items.append(updatedItem)
            }
            list = IBGShoppingList(id: current.id, name: current.name, items: items)
            _ = current // silence unused warning
        }
        sse.connect(listId: listId)
    }
}

// MARK: - Row

private struct StorePriceRow: View {
    let item: IBGListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                if let urlStr = item.recommended?.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Image(systemName: "photo")
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.cardBorder)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "cart.fill")
                                .foregroundStyle(Theme.textMuted)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.rawText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    stateRow

                    if let cand = item.recommended {
                        Text(cand.productTitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(String(format: "$%.2f", cand.price))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accent)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                            Text(cand.storeName)
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                            if let unit = cand.unitPriceLabel {
                                Text("· \(unit)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(12)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stateRow: some View {
        HStack(spacing: 6) {
            stateChip
            if let progress = item.searchProgress,
               progress.state == "running" {
                Text("\(progress.completedProviders)/\(progress.totalProviders) providers")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var stateChip: some View {
        let (text, color, showSpinner): (String, Color, Bool) = {
            switch item.state {
            case .queued:         return ("Queued",       Theme.textMuted, false)
            case .searching:      return ("Searching",    Theme.accent,    true)
            case .needsReview:    return ("Needs review", .orange,         false)
            case .recommended:    return ("Recommended",  .green,          false)
            case .selected:       return ("Selected",     Theme.accent,    false)
            case .purchased:      return ("Purchased",    .green,          false)
            case .stale:          return ("Stale",        Theme.textMuted, false)
            case .providerError:  return ("Error",        Theme.destructive, false)
            case .unknown:        return ("—",            Theme.textMuted, false)
            }
        }()

        HStack(spacing: 4) {
            if showSpinner {
                ProgressView().scaleEffect(0.6).tint(color)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
