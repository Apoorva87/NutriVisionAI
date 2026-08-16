// GroceryCandidatesSheet — Sheet shown when a Store Prices row is tapped.
// Displays grouped candidates across stores, offers quick-action re-searches,
// and lets the user pick a specific candidate as the selection for that list item.

import SwiftUI

struct GroceryCandidatesSheet: View {
    let itemId: Int
    let itemLabel: String
    let currentSelectionId: Int?
    let onSelectionChanged: (IBGShoppingList) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [IBGCandidateGroup] = []
    @State private var storeLinks: [IBGCandidate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let quickActions: [(id: String, label: String, icon: String)] = [
        ("cheaper", "Cheaper", "dollarsign"),
        ("bigger", "Bigger", "plus.magnifyingglass"),
        ("not-this-type", "Different type", "arrow.triangle.2.circlepath"),
        ("any-store", "Any store", "building.2"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if isLoading && groups.isEmpty && storeLinks.isEmpty {
                    ProgressView("Loading candidates…")
                } else if let err = errorMessage, groups.isEmpty && storeLinks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.textMuted)
                        Text(err)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal)
                        Button("Retry") { Task { await reload() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(Theme.destructive)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(Theme.destructive)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Button("Retry") { Task { await reload() } }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                }
                                .padding(10)
                                .themedCard()
                            }

                            quickActionsBar
                            if groups.isEmpty && storeLinks.isEmpty {
                                VStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundStyle(Theme.textMuted)
                                    Text("No candidates yet")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Providers may still be searching, or none returned results.")
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(30)
                            } else {
                                ForEach(groups) { group in
                                    CandidateGroupCard(
                                        group: group,
                                        currentSelectionId: currentSelectionId,
                                        onSelect: { candidate in
                                            Task { await select(candidate) }
                                        }
                                    )
                                }
                                if !storeLinks.isEmpty {
                                    StoreLinksSection(links: storeLinks)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(itemLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    // MARK: - Quick actions

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickActions, id: \.id) { action in
                    Button {
                        Task { await runQuickAction(action.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: action.icon)
                            Text(action.label)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.1))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            async let groupsTask = IBuyGroceryClient.shared.candidateGroups(itemId: itemId)
            async let linksTask  = IBuyGroceryClient.shared.storeLinks(itemId: itemId)
            groups = try await groupsTask
            storeLinks = try await linksTask
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func select(_ candidate: IBGCandidate) async {
        do {
            let updated = try await IBuyGroceryClient.shared.selectCandidate(
                itemId: itemId,
                candidateItemId: candidate.id
            )
            onSelectionChanged(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runQuickAction(_ action: String) async {
        do {
            let updated = try await IBuyGroceryClient.shared.quickAction(itemId: itemId, action: action)
            onSelectionChanged(updated)
            // Don't dismiss — the user will want to see the new candidates
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Group card

private struct CandidateGroupCard: View {
    let group: IBGCandidateGroup
    let currentSelectionId: Int?
    let onSelect: (IBGCandidate) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let urlStr = group.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                        default: Color.clear
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let brand = group.brand {
                        Text(brand)
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }
                    HStack(spacing: 6) {
                        Text(String(format: "$%.2f", group.bestPrice))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                        if let size = group.sizeText {
                            Text("· \(size)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        Text("· \(group.storeCount) store\(group.storeCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(Array((expanded ? group.offers : Array(group.offers.prefix(2))).enumerated()), id: \.offset) { _, offer in
                    CandidateRow(
                        candidate: offer,
                        isSelected: currentSelectionId == offer.id,
                        onSelect: { onSelect(offer) }
                    )
                }
                if group.offers.count > 2 {
                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Text(expanded ? "Show less" : "Show \(group.offers.count - 2) more")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(12)
        .themedCard()
    }
}

// MARK: - Single-candidate row

private struct CandidateRow: View {
    let candidate: IBGCandidate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.storeName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                if let unit = candidate.unitPriceLabel {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(String(format: "$%.2f", candidate.price))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            if let urlStr = candidate.productUrl, let url = URL(string: urlStr) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Store links

private struct StoreLinksSection: View {
    let links: [IBGCandidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Other Stores")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
                .textCase(.uppercase)
                .tracking(1)
            ForEach(links) { link in
                if let urlStr = link.productUrl, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.accent)
                            Text("Search on \(link.storeName)")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(Theme.textMuted)
                        }
                        .font(.caption)
                        .padding(10)
                        .themedCard()
                    }
                }
            }
        }
    }
}
