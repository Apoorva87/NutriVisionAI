import SwiftUI

struct SettingsView: View {
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
    @State private var isLoggedIn = false
    @State private var showLoginSheet = false
    
    // Server URL
    @State private var serverURL: String = ""
    @State private var showServerURLSheet = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Section
                Section {
                    if let user = currentUser, !user.isSystem! {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.body)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Log out") {
                                logout()
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            showLoginSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                Text("Sign In")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Sign in to sync your data across devices")
                }
                
                // Nutrition Goals Section
                Section {
                    HStack {
                        Text("Daily Calories")
                        Spacer()
                        TextField("2000", text: $calorieGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("150", text: $proteinGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("200", text: $carbsGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("65", text: $fatGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nutrition Goals")
                }
                
                // AI Configuration Section
                Section {
                    Picker("AI Provider", selection: $modelProvider) {
                        Text("LM Studio").tag("lmstudio")
                        Text("OpenAI").tag("openai")
                    }
                    
                    Picker("Portion Style", selection: $portionStyle) {
                        Text("Quick").tag("quick")
                        Text("Detailed").tag("detailed")
                    }
                } header: {
                    Text("AI Settings")
                }
                
                // LM Studio Settings
                if modelProvider == "lmstudio" {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Base URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("http://localhost:1234", text: $lmstudioBaseUrl)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vision Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("qwen/qwen3-vl-8b", text: $lmstudioVisionModel)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Portion Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("qwen/qwen3-vl-8b", text: $lmstudioPortionModel)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text("LM Studio Configuration")
                    }
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
                                Text(APIClient.shared.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Connection")
                }
                
                // Save Button
                Section {
                    Button {
                        saveSettings()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save Settings")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
                
                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .refreshable {
                await loadSettings()
            }
            .task {
                await loadSettings()
                await loadCurrentUser()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
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
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
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
        }
    }
    
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
            isLoggedIn = !(user.isSystem ?? true)
        } catch {
            currentUser = nil
            isLoggedIn = false
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
                    
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter your name and email to sign in or create an account")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Button {
                        login()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(name.isEmpty || email.isEmpty || isLoading)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
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
                } header: {
                    Text("Server URL")
                } footer: {
                    Text("Enter the URL of your NutriVision backend server")
                }
                
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(serverURL.isEmpty || isTesting)
                    
                    if let result = testResult {
                        HStack {
                            Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.contains("Success") ? .green : .red)
                            Text(result)
                                .font(.caption)
                        }
                    }
                }
                
                Section {
                    Text("For simulator: http://localhost:8000")
                    Text("For device: http://YOUR_MAC_IP:8000")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Server URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
                        testResult = "Success - Connected!"
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
