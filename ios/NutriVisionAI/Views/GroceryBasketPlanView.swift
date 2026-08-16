// GroceryBasketPlanView — Compare simplest vs. cheapest basket plans and per-store breakdowns.

import SwiftUI

struct GroceryBasketPlanView: View {
    let listId: Int

    @State private var mode: String = "cheapest"
    @State private var plan: IBGBasketPlan?
    @State private var stores: [IBGAvailableStore] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let modes: [(id: String, label: String)] = [
        ("cheapest", "Cheapest"),
        ("simplest", "Simplest"),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if isLoading && plan == nil {
                ProgressView("Building plan…")
            } else if let err = errorMessage, plan == nil {
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
                }
            } else if let plan = plan {
                content(plan: plan)
            }
        }
        .navigationTitle("Basket Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func content(plan: IBGBasketPlan) -> some View {
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
                    .padding(.horizontal)
                }

                Picker("Mode", selection: $mode) {
                    ForEach(modes, id: \.id) { m in
                        Text(m.label).tag(m.id)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in Task { await reload() } }
                .padding(.horizontal)

                VStack(spacing: 4) {
                    Text(String(format: "$%.2f", plan.total))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("\(plan.storeCount) store\(plan.storeCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .themedCard()
                .padding(.horizontal)

                ForEach(plan.buckets) { bucket in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(bucket.storeName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "$%.2f", bucket.total))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accent)
                        }
                        ForEach(bucket.lines) { line in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.needLabel)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(line.productTitle)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textMuted)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(String(format: "$%.2f", line.price))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(12)
                    .themedCard()
                    .padding(.horizontal)
                }

                if !stores.isEmpty {
                    Text("Single-store plans")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textMuted)
                        .textCase(.uppercase)
                        .tracking(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    ForEach(stores) { store in
                        NavigationLink {
                            GroceryBasketStoreView(listId: listId, store: store)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.storeName)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(store.itemCount)/\(store.totalItems) items")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .padding(12)
                            .themedCard()
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            async let planTask = IBuyGroceryClient.shared.basket(listId: listId, mode: mode)
            async let storesTask = IBuyGroceryClient.shared.basketStores(listId: listId)
            plan = try await planTask
            do {
                stores = try await storesTask
            } catch {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Single-store plan

struct GroceryBasketStoreView: View {
    let listId: Int
    let store: IBGAvailableStore
    @State private var plan: IBGBasketPlan?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let plan = plan, let bucket = plan.buckets.first {
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text(store.storeName)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(String(format: "$%.2f", plan.total))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                            Text("\(store.itemCount)/\(store.totalItems) items available")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .themedCard()

                        ForEach(bucket.lines) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.needLabel)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(line.productTitle)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textMuted)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(String(format: "$%.2f", line.price))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(10)
                            .themedCard()
                        }
                    }
                    .padding()
                }
            } else if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(store.storeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task {
            do {
                plan = try await IBuyGroceryClient.shared.basket(listId: listId, mode: "store", storeId: store.storeId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
