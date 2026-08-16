// IBuyGrocerySettingsView — Configure the Store Prices (iBuyGrocery) integration:
// backend URL, ZIP, optimize mode, provider enable/disable, and store pickers.

import SwiftUI

struct IBuyGrocerySettingsView: View {
    @State private var baseURL: String = IBuyGroceryClient.shared.baseURL
    @State private var apiKey: String = IBuyGroceryClient.shared.apiToken ?? ""
    @State private var pingMessage: String?
    @State private var pingOK: Bool?
    @State private var identity: IBGUserMe?

    @State private var settings: IBGSettings?
    @State private var providers: [IBGProvider] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var storeSheetProvider: IBGProvider?

    private var isRemoteURL: Bool {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)),
              let host = url.host else { return false }
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") {
            return false
        }
        return true
    }

    private var isInsecureRemote: Bool {
        isRemoteURL && baseURL.lowercased().hasPrefix("http://")
    }

    var body: some View {
        Form {
            // ── Server URL ──
            Section {
                TextField("https://grocery.apoorvakarnik.top", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .foregroundStyle(Theme.textPrimary)

                SecureField("API key (sk_search_…)", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.textPrimary)

                Button("Save & Test") { saveAndTest() }
                    .foregroundStyle(Theme.accent)

                if isInsecureRemote {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Remote host without HTTPS — traffic is unencrypted.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let msg = pingMessage {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(pingOK == true ? Color.green : Theme.destructive)
                            .frame(width: 7, height: 7)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(pingOK == true ? .green : Theme.destructive)
                    }
                }

                if let identity = identity {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill.badge.checkmark")
                            .foregroundStyle(.green)
                        Text("Signed in as \(identity.displayName ?? identity.email)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                Text("Backend")
                    .foregroundStyle(Theme.textMuted)
            } footer: {
                Text(isRemoteURL
                     ? "Points the app at your hosted iBuyGrocery backend. Mint an API key at apoorvakarnik.top/account and paste it here."
                     : "For local dev, run ./run.sh in ~/experiments/iBuyGrocery (port 8766). When IBG_DEV_USER_EMAIL is set on the server, no key is required.")
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.cardSurface)

            if let settings = settings {
                // ── Shopping settings ──
                Section {
                    HStack {
                        Text("ZIP code")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("e.g. 95051", text: zipBinding(settings))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(maxWidth: 140)
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Picker("Optimize", selection: modeBinding(settings)) {
                        ForEach(IBGOptimizeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)

                    Toggle("Ignore sponsored results", isOn: sponsoredBinding(settings))
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.textPrimary)

                    Stepper(
                        value: limitBinding(settings),
                        in: 1...50
                    ) {
                        HStack {
                            Text("Results per provider")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(settings.perProviderLimit)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    Text("Shopping Preferences")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)
            }

            // ── Providers ──
            if !providers.isEmpty {
                Section {
                    ForEach(providers) { p in
                        providerRow(p)
                    }
                } header: {
                    Text("Stores")
                        .foregroundStyle(Theme.textMuted)
                } footer: {
                    Text("Enable the stores you want iBuyGrocery to search. Some stores need a ZIP code or store selection.")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)
            }

            if let err = errorMessage {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                }
            }

            if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Store Prices")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $storeSheetProvider) { provider in
            ProviderStorePickerSheet(provider: provider) { updated in
                if let idx = providers.firstIndex(where: { $0.id == updated.id }) {
                    providers[idx] = updated
                }
            }
        }
    }

    // MARK: - Provider row

    @ViewBuilder
    private func providerRow(_ provider: IBGProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: Binding(
                    get: { provider.enabled },
                    set: { newVal in Task { await toggleProvider(provider, enabled: newVal) } }
                )) {
                    Text(provider.displayName)
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
            }
            HStack(spacing: 4) {
                statusBadge(provider)
                if let store = provider.selectedStoreName {
                    Text("· \(store)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if provider.locationMode == .storePicker {
                    Button("Pick store") {
                        storeSheetProvider = provider
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ provider: IBGProvider) -> some View {
        let (text, color): (String, Color) = {
            switch provider.locationStatus {
            case .ready:            return ("Ready", .green)
            case .zipRequired:      return ("Needs ZIP", .orange)
            case .selectionNeeded:  return ("Pick store", .orange)
            case .searchOnly:       return ("Search links only", Theme.textMuted)
            case .zipOptional:      return ("ZIP optional", Theme.textMuted)
            }
        }()
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Bindings that patch the settings on change

    private func zipBinding(_ s: IBGSettings) -> Binding<String> {
        Binding(
            get: { s.zipCode ?? "" },
            set: { newVal in
                Task {
                    await patchSettings(IBGSettingsPatch(
                        optimizeMode: nil, preferredStore: nil,
                        zipCode: newVal.trimmingCharacters(in: .whitespaces),
                        ignoreSponsored: nil, perProviderLimit: nil, perItemLimit: nil
                    ))
                }
            }
        )
    }

    private func modeBinding(_ s: IBGSettings) -> Binding<IBGOptimizeMode> {
        Binding(
            get: { s.optimizeMode },
            set: { newVal in
                Task {
                    await patchSettings(IBGSettingsPatch(
                        optimizeMode: newVal, preferredStore: nil, zipCode: nil,
                        ignoreSponsored: nil, perProviderLimit: nil, perItemLimit: nil
                    ))
                }
            }
        )
    }

    private func sponsoredBinding(_ s: IBGSettings) -> Binding<Bool> {
        Binding(
            get: { s.ignoreSponsored },
            set: { newVal in
                Task {
                    await patchSettings(IBGSettingsPatch(
                        optimizeMode: nil, preferredStore: nil, zipCode: nil,
                        ignoreSponsored: newVal, perProviderLimit: nil, perItemLimit: nil
                    ))
                }
            }
        )
    }

    private func limitBinding(_ s: IBGSettings) -> Binding<Int> {
        Binding(
            get: { s.perProviderLimit },
            set: { newVal in
                Task {
                    await patchSettings(IBGSettingsPatch(
                        optimizeMode: nil, preferredStore: nil, zipCode: nil,
                        ignoreSponsored: nil, perProviderLimit: newVal, perItemLimit: nil
                    ))
                }
            }
        )
    }

    // MARK: - Actions

    private func saveAndTest() {
        IBuyGroceryClient.shared.baseURL = baseURL
        IBuyGroceryClient.shared.setAPIToken(apiKey)
        // Reflect normalization (trailing slash strip) back into the field.
        baseURL = IBuyGroceryClient.shared.baseURL
        Task { await pingAndReload() }
    }

    private func pingAndReload() async {
        let (ok, message) = await IBuyGroceryClient.shared.ping()
        pingOK = ok
        pingMessage = message
        identity = nil
        if ok {
            // Resolve identity (best-effort — silent on 401 since the URL
            // could be reachable but the user hasn't pasted a key yet).
            identity = try? await IBuyGroceryClient.shared.authMe()
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            async let settingsTask = IBuyGroceryClient.shared.getSettings()
            async let providersTask = IBuyGroceryClient.shared.listProviders()
            async let identityTask: IBGUserMe? = try? await IBuyGroceryClient.shared.authMe()
            settings = try await settingsTask
            providers = try await providersTask
            identity = await identityTask
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func patchSettings(_ patch: IBGSettingsPatch) async {
        do {
            settings = try await IBuyGroceryClient.shared.patchSettings(patch)
            // ZIP change may re-calc provider location_status
            providers = try await IBuyGroceryClient.shared.listProviders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleProvider(_ provider: IBGProvider, enabled: Bool) async {
        do {
            let updated = try await IBuyGroceryClient.shared.setProviderEnabled(
                providerId: provider.id,
                enabled: enabled
            )
            if let idx = providers.firstIndex(where: { $0.id == updated.id }) {
                providers[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Store picker sheet

private struct ProviderStorePickerSheet: View {
    let provider: IBGProvider
    let onSelected: (IBGProvider) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: [IBGProviderStoreOption] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Looking up stores…")
                } else if let err = errorMessage {
                    VStack(spacing: 8) {
                        Text(err)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.destructive)
                        Button("Retry") { Task { await load() } }
                    }
                    .padding()
                } else if options.isEmpty {
                    Text("No store options returned. Check your ZIP code.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding()
                } else {
                    List {
                        ForEach(options) { option in
                            Button {
                                Task { await select(option) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.storeName)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(option.locationLabel)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            .listRowBackground(Theme.cardSurface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .background(Theme.background)
            .navigationTitle("Pick \(provider.displayName) store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            options = try await IBuyGroceryClient.shared.providerStoreOptions(providerId: provider.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func select(_ option: IBGProviderStoreOption) async {
        do {
            let updated = try await IBuyGroceryClient.shared.selectProviderStore(
                providerId: provider.id,
                externalStoreId: option.externalStoreId
            )
            onSelected(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
