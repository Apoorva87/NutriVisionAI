import SwiftUI

// MARK: - Provider Sheet Wrapper

private struct ProviderSheet: Identifiable {
    let id: String  // "openai", "google", "anthropic"
}

// MARK: - Cloud Provider Sheet

private struct CloudProviderSheet: View {
    let provider: String

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var baseURL: String = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var isSaving = false

    private var providerTitle: String {
        switch provider {
        case "openai": return "OpenAI"
        case "google": return "Google AI"
        case "anthropic": return "Anthropic"
        default: return provider.capitalized
        }
    }

    private var models: [String] {
        switch provider {
        case "openai": return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case "google": return ["gemini-1.5-pro", "gemini-1.5-flash"]
        case "anthropic": return ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022"]
        default: return []
        }
    }

    private var isComingSoon: Bool {
        provider == "google" || provider == "anthropic"
    }

    var body: some View {
        NavigationStack {
            Form {
                if isComingSoon {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text("Coming soon \u{2014} requires backend support")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.accent.opacity(0.08))
                    }
                }

                Section {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.textPrimary)
                } header: {
                    Text("Authentication")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                Section {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textSecondary)
                } header: {
                    Text("Model")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                if provider == "openai" {
                    Section {
                        TextField("https://api.openai.com/v1", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.textPrimary)
                    } header: {
                        Text("Base URL (optional)")
                            .foregroundStyle(Theme.textMuted)
                    } footer: {
                        Text("Override for OpenAI-compatible APIs")
                            .foregroundStyle(Theme.textMuted)
                    }
                    .listRowBackground(Theme.cardSurface)
                }

                Section {
                    GradientButton(title: "Save", isLoading: isSaving, isDisabled: apiKey.isEmpty || isComingSoon) {
                        saveProviderConfig()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if isTesting {
                                ProgressView().tint(Theme.accent)
                            }
                        }
                    }
                    .disabled(apiKey.isEmpty || isTesting || isComingSoon)
                    .listRowBackground(Theme.cardSurface)

                    if let result = testResult {
                        HStack {
                            Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.contains("Success") ? Theme.successStart : Theme.destructive)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(providerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .onAppear {
                apiKey = KeychainHelper.read(key: "\(provider)_api_key") ?? ""
                baseURL = UserDefaults.standard.string(forKey: "\(provider)_base_url") ?? ""
                selectedModel = UserDefaults.standard.string(forKey: "\(provider)_model") ?? models.first ?? ""
            }
        }
    }

    private func saveProviderConfig() {
        isSaving = true
        if !apiKey.isEmpty {
            try? KeychainHelper.save(key: "\(provider)_api_key", value: apiKey)
        }
        UserDefaults.standard.set(selectedModel, forKey: "\(provider)_model")
        if !baseURL.isEmpty {
            UserDefaults.standard.set(baseURL, forKey: "\(provider)_base_url")
        }
        isSaving = false
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                _ = try await APIClient.shared.getSettings()
                await MainActor.run {
                    testResult = "Success \u{2014} Connected!"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var analysisService = FoodAnalysisService.shared
    @State private var settings: SettingsResponse?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccessToast = false

    // Editable fields
    @State private var calorieGoal: String = ""
    @State private var proteinGoal: String = ""
    @State private var carbsGoal: String = ""
    @State private var fatGoal: String = ""
    @State private var modelProvider: String = "lmstudio"
    @State private var lmstudioBaseUrl: String = ""
    @State private var lmstudioVisionModel: String = ""
    @State private var lmstudioPortionModel: String = ""
    @State private var portionStyle: String = "quick"

    // Auth state
    @State private var currentUser: UserInfo?

    @State private var showLoginSheet = false

    // Server URL
    @State private var serverURL: String = ""
    @State private var showServerURLSheet = false

    // Multi-provider
    @State private var selectedLLMProvider: String = "lmstudio"
    @State private var showProviderSheet: ProviderSheet? = nil

    private var initials: String {
        guard let name = currentUser?.name else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        } else if let first = parts.first {
            return String(first.prefix(1)).uppercased()
        }
        return "?"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Account Section
                Section {
                    if let user = currentUser, !(user.isSystem ?? true) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.accentGradient)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(initials)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("Log out") {
                                logout()
                            }
                            .foregroundStyle(Theme.destructive)
                        }
                    } else {
                        Button {
                            showLoginSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                    .foregroundStyle(Theme.accent)
                                Text("Sign In")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                } header: {
                    Text("Account")
                        .foregroundStyle(Theme.textMuted)
                } footer: {
                    Text("Sign in to sync your data across devices")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                // Analysis Provider Section
                analysisProviderSection

                // Nutrition Goals Section
                Section {
                    HStack {
                        Text("Daily Calories")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("2000", text: $calorieGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .foregroundStyle(Theme.textPrimary)
                        Text("kcal")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack {
                        Text("Protein")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("150", text: $proteinGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .foregroundStyle(Theme.textPrimary)
                        Text("g")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack {
                        Text("Carbs")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("200", text: $carbsGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .foregroundStyle(Theme.textPrimary)
                        Text("g")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack {
                        Text("Fat")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("65", text: $fatGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .foregroundStyle(Theme.textPrimary)
                        Text("g")
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Nutrition Goals")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                // Multi-Provider AI Configuration
                Section {
                    providerCard(
                        icon: "desktopcomputer",
                        iconGradient: [Color(red: 34/255, green: 197/255, blue: 94/255), Color(red: 22/255, green: 163/255, blue: 74/255)],
                        title: "Local Server",
                        subtitle: "LM Studio / Ollama",
                        isActive: selectedLLMProvider == "lmstudio"
                    ) {
                        selectedLLMProvider = "lmstudio"
                        modelProvider = "lmstudio"
                    }

                    if selectedLLMProvider == "lmstudio" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Base URL")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            TextField("http://localhost:1234", text: $lmstudioBaseUrl)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .listRowBackground(Theme.cardSurface)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vision Model")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            TextField("qwen/qwen3-vl-8b", text: $lmstudioVisionModel)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .listRowBackground(Theme.cardSurface)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Portion Model")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            TextField("qwen/qwen3-vl-8b", text: $lmstudioPortionModel)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .listRowBackground(Theme.cardSurface)
                    }

                    providerCard(
                        icon: "brain",
                        iconGradient: [Color(red: 16/255, green: 163/255, blue: 127/255), Color(red: 52/255, green: 211/255, blue: 153/255)],
                        title: "OpenAI",
                        subtitle: "GPT-4o, GPT-4o mini",
                        isActive: selectedLLMProvider == "openai"
                    ) {
                        selectedLLMProvider = "openai"
                        modelProvider = "openai"
                        showProviderSheet = ProviderSheet(id: "openai")
                    }

                    providerCard(
                        icon: "sparkles",
                        iconGradient: [Color(red: 59/255, green: 130/255, blue: 246/255), Color(red: 37/255, green: 99/255, blue: 235/255)],
                        title: "Google AI",
                        subtitle: "Gemini 1.5 Pro / Flash",
                        isActive: selectedLLMProvider == "google"
                    ) {
                        selectedLLMProvider = "google"
                        modelProvider = "google"
                        showProviderSheet = ProviderSheet(id: "google")
                    }

                    providerCard(
                        icon: "bubble.left.and.text.bubble.right",
                        iconGradient: [Color(red: 217/255, green: 119/255, blue: 6/255), Color(red: 245/255, green: 158/255, blue: 11/255)],
                        title: "Anthropic",
                        subtitle: "Claude Sonnet / Haiku",
                        isActive: selectedLLMProvider == "anthropic"
                    ) {
                        selectedLLMProvider = "anthropic"
                        modelProvider = "anthropic"
                        showProviderSheet = ProviderSheet(id: "anthropic")
                    }

                    Picker("Portion Style", selection: $portionStyle) {
                        Text("Quick").tag("quick")
                        Text("Detailed").tag("detailed")
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textSecondary)
                    .listRowBackground(Theme.cardSurface)
                } header: {
                    Text("AI Provider")
                        .foregroundStyle(Theme.textMuted)
                }

                // Server Configuration Section
                Section {
                    Button {
                        serverURL = APIClient.shared.baseURL
                        showServerURLSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Server URL")
                                    .foregroundStyle(Theme.textPrimary)
                                Text(APIClient.shared.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                } header: {
                    Text("Connection")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                // Save Button
                Section {
                    GradientButton(title: "Save Settings", isLoading: isSaving) {
                        saveSettings()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // App Info
                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("About")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationTitle("Settings")
            .refreshable {
                await loadSettings()
            }
            .task {
                await loadSettings()
                await loadCurrentUser()
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if showSuccessToast {
                    VStack {
                        Spacer()
                        Text("Settings saved")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .padding()
                            .background(Theme.cardSurface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.bottom, 32)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginSheet(onLogin: {
                    Task { await loadCurrentUser() }
                })
            }
            .sheet(isPresented: $showServerURLSheet) {
                ServerURLSheet(serverURL: $serverURL, onSave: {
                    APIClient.shared.baseURL = serverURL
                    Task {
                        await loadSettings()
                        await loadCurrentUser()
                    }
                })
            }
            .sheet(item: $showProviderSheet) { sheet in
                CloudProviderSheet(provider: sheet.id)
            }
        }
    }

    // MARK: - Analysis Provider Section

    private var analysisProviderSection: some View {
        Section {
            ForEach(analysisService.availableProviders, id: \.self) { (provider: AnalysisProviderType) in
                Button {
                    analysisService.currentProvider = provider
                } label: {
                    HStack {
                        Image(systemName: provider.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.rawValue)
                                .foregroundStyle(Theme.textPrimary)
                            Text(provider.description)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if analysisService.currentProvider == provider {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        } header: {
            Text("Image Analysis")
                .foregroundStyle(Theme.textMuted)
        } footer: {
            if analysisService.availableProviders.count == 1 {
                Text("Apple Foundation Models requires iOS 26+ and is only available in the AppleAI build configuration.")
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .listRowBackground(Theme.cardSurface)
    }

    // MARK: - Provider Card

    @ViewBuilder
    private func providerCard(icon: String, iconGradient: [Color], title: String, subtitle: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 32, height: 32)
                    .background(LinearGradient(colors: iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .listRowBackground(isActive ? Theme.accent.opacity(0.06) : Theme.cardSurface)
        .accessibilityLabel("\(title), \(subtitle), \(isActive ? "active" : "inactive")")
        .accessibilityHint("Double tap to select this provider")
    }

    // MARK: - Data Loading

    private func loadSettings() async {
        isLoading = true
        do {
            let response = try await APIClient.shared.getSettings()
            settings = response

            // Populate editable fields
            calorieGoal = String(response.calorieGoal)
            proteinGoal = String(response.proteinG)
            carbsGoal = String(response.carbsG)
            fatGoal = String(response.fatG)
            modelProvider = response.modelProvider ?? "lmstudio"
            selectedLLMProvider = modelProvider
            lmstudioBaseUrl = response.lmstudioBaseUrl ?? "http://localhost:1234"
            lmstudioVisionModel = response.lmstudioVisionModel ?? ""
            lmstudioPortionModel = response.lmstudioPortionModel ?? ""
            portionStyle = response.portionEstimationStyle ?? "quick"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadCurrentUser() async {
        do {
            let user = try await APIClient.shared.me()
            currentUser = user
        } catch {
            currentUser = nil
        }
    }

    private func saveSettings() {
        isSaving = true

        let payload = SettingsPayload(
            currentUserName: settings?.currentUserName,
            calorieGoal: Int(calorieGoal) ?? 2000,
            proteinG: Int(proteinGoal) ?? 150,
            carbsG: Int(carbsGoal) ?? 200,
            fatG: Int(fatGoal) ?? 65,
            modelProvider: modelProvider,
            portionEstimationStyle: portionStyle,
            lmstudioBaseUrl: lmstudioBaseUrl.isEmpty ? nil : lmstudioBaseUrl,
            lmstudioVisionModel: lmstudioVisionModel.isEmpty ? nil : lmstudioVisionModel,
            lmstudioPortionModel: lmstudioPortionModel.isEmpty ? nil : lmstudioPortionModel
        )

        Task {
            do {
                _ = try await APIClient.shared.updateSettings(payload)
                await MainActor.run {
                    isSaving = false
                    withAnimation {
                        showSuccessToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showSuccessToast = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func logout() {
        Task {
            do {
                try await APIClient.shared.logout()
                await loadCurrentUser()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Login Sheet

struct LoginSheet: View {
    let onLogin: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.textPrimary)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.textPrimary)
                } footer: {
                    Text("Enter your name and email to sign in or create an account")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(Theme.destructive)
                    }
                    .listRowBackground(Theme.cardSurface)
                }

                Section {
                    GradientButton(title: "Sign In", isLoading: isLoading, isDisabled: name.isEmpty || email.isEmpty) {
                        login()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await APIClient.shared.login(name: name, email: email)
                await MainActor.run {
                    isLoading = false
                    onLogin()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Server URL Sheet

struct ServerURLSheet: View {
    @Binding var serverURL: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://localhost:8000", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .foregroundStyle(Theme.textPrimary)
                } header: {
                    Text("Server URL")
                        .foregroundStyle(Theme.textMuted)
                } footer: {
                    Text("Enter the URL of your NutriVision backend server")
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Theme.cardSurface)

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if isTesting {
                                ProgressView().tint(Theme.accent)
                            }
                        }
                    }
                    .disabled(serverURL.isEmpty || isTesting)
                    .listRowBackground(Theme.cardSurface)

                    if let result = testResult {
                        HStack {
                            Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.contains("Success") ? Theme.successStart : Theme.destructive)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardSurface)
                    }
                }

                Section {
                    Text("For simulator: http://localhost:8000")
                        .foregroundStyle(Theme.textSecondary)
                    Text("For device: http://YOUR_MAC_IP:8000")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.caption)
                .listRowBackground(Theme.cardSurface)

                Section {
                    GradientButton(title: "Save", isDisabled: serverURL.isEmpty) {
                        onSave()
                        dismiss()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Server URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        guard let url = URL(string: "\(serverURL)/api/v1/dashboard") else {
            testResult = "Invalid URL"
            isTesting = false
            return
        }

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    await MainActor.run {
                        testResult = "Success \u{2014} Connected!"
                        isTesting = false
                    }
                } else {
                    await MainActor.run {
                        testResult = "Server responded with error"
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
