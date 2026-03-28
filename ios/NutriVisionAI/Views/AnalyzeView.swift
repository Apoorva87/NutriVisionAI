import SwiftUI
import PhotosUI

struct AnalyzeView: View {
    @StateObject private var analysisService = FoodAnalysisService.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var analysisResult: AnalysisResponse?
    @State private var editableItems: [EditableAnalysisItem] = []
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var mealName = ""
    @State private var isSaving = false
    @State private var showSuccessAlert = false
    @State private var showProviderPicker = false
    @State private var showQuickSearch = false
    
    private var totalCalories: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.calories * $1.gramsMultiplier }
    }

    private var totalProtein: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.proteinG * $1.gramsMultiplier }
    }

    private var totalCarbs: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.carbsG * $1.gramsMultiplier }
    }

    private var totalFat: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.fatG * $1.gramsMultiplier }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if capturedImage == nil && analysisResult == nil {
                    // Image capture state
                    ImageCaptureView(
                        showCamera: $showCamera,
                        selectedPhoto: $selectedPhoto,
                        onImageSelected: analyzeImage
                    )
                } else if isAnalyzing {
                    // Analyzing state
                    AnalyzingProgressView(image: capturedImage)
                } else if let error = errorMessage {
                    // Error state
                    ErrorStateView(
                        message: error,
                        onRetry: reset,
                        onCancel: reset
                    )
                } else if analysisResult != nil {
                    // Results state
                    AnalysisResultsView(
                        image: capturedImage,
                        editableItems: $editableItems,
                        mealName: $mealName,
                        totalCalories: totalCalories,
                        totalProtein: totalProtein,
                        totalCarbs: totalCarbs,
                        totalFat: totalFat,
                        isSaving: isSaving,
                        showQuickSearch: $showQuickSearch,
                        onSave: saveMeal,
                        onCancel: reset
                    )
                }
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(analysisService.availableProviders) { provider in
                            Button {
                                analysisService.currentProvider = provider
                            } label: {
                                HStack {
                                    Label(provider.rawValue, systemImage: provider.systemImage)
                                    if analysisService.currentProvider == provider {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Provider", systemImage: analysisService.currentProvider.systemImage)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, newImage in
                if newImage != nil {
                    Task { await performAnalysis() }
                }
            }
            .alert("Meal Saved", isPresented: $showSuccessAlert) {
                Button("OK") { reset() }
            } message: {
                Text("Your meal has been logged successfully.")
            }
            .sheet(isPresented: $showQuickSearch) {
                QuickFoodSearchSheet { newItem in
                    editableItems.append(newItem)
                }
            }
        }
    }
    
    private func analyzeImage(_ imageData: Data) {
        capturedImage = UIImage(data: imageData)
    }
    
    private func performAnalysis() async {
        guard let image = capturedImage else { return }
        
        isAnalyzing = true
        errorMessage = nil
        
        do {
            // Use the abstracted analysis service (backend or Apple Foundation Models)
            let result = try await analysisService.analyzeImage(image)
            analysisResult = result
            editableItems = result.items.map { EditableAnalysisItem(item: $0) }
            
            // Generate default meal name
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            mealName = "Meal at \(timeFormatter.string(from: Date()))"
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isAnalyzing = false
    }
    
    private func saveMeal() {
        let includedItems = editableItems
            .filter { $0.isIncluded }
            .map { editable -> AnalysisItem in
                AnalysisItem(
                    detectedName: editable.item.detectedName,
                    canonicalName: editable.item.canonicalName,
                    portionLabel: editable.item.portionLabel,
                    estimatedGrams: editable.adjustedGrams,
                    uncertainty: editable.item.uncertainty,
                    confidence: editable.item.confidence,
                    calories: editable.item.calories * editable.gramsMultiplier,
                    proteinG: editable.item.proteinG * editable.gramsMultiplier,
                    carbsG: editable.item.carbsG * editable.gramsMultiplier,
                    fatG: editable.item.fatG * editable.gramsMultiplier,
                    visionConfidence: editable.item.visionConfidence,
                    dbMatch: editable.item.dbMatch,
                    nutritionAvailable: editable.item.nutritionAvailable
                )
            }

        guard !includedItems.isEmpty else {
            errorMessage = "Please include at least one item"
            return
        }

        isSaving = true

        if FoodAnalysisService.shared.isCloudMode {
            let name = mealName.isEmpty ? "Scanned Meal" : mealName
            let _ = LocalMealStore.shared.saveMeal(name: name, image: capturedImage, items: includedItems)
            isSaving = false
            showSuccessAlert = true
        } else {
            Task {
                do {
                    let mealItems = includedItems.map { item in
                        MealItemInput(
                            detectedName: item.detectedName,
                            canonicalName: item.canonicalName,
                            portionLabel: item.portionLabel,
                            estimatedGrams: item.estimatedGrams,
                            uncertainty: item.uncertainty,
                            confidence: item.confidence
                        )
                    }
                    let request = CreateMealRequest(
                        mealName: mealName.isEmpty ? "Scanned Meal" : mealName,
                        imagePath: analysisResult?.imagePath,
                        items: mealItems
                    )
                    _ = try await APIClient.shared.createMeal(request)
                    await MainActor.run {
                        isSaving = false
                        showSuccessAlert = true
                    }
                } catch {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    private func reset() {
        capturedImage = nil
        selectedPhoto = nil
        analysisResult = nil
        editableItems = []
        errorMessage = nil
        mealName = ""
        isSaving = false
    }
}

// MARK: - Editable Item Wrapper

struct EditableAnalysisItem: Identifiable {
    let id = UUID()
    let item: AnalysisItem
    var isIncluded: Bool = true
    var gramsMultiplier: Double = 1.0
    
    var adjustedGrams: Double {
        item.estimatedGrams * gramsMultiplier
    }
}

// MARK: - Image Capture View

struct ImageCaptureView: View {
    @Binding var showCamera: Bool
    @Binding var selectedPhoto: PhotosPickerItem?
    let onImageSelected: (Data) -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(Theme.textSecondary)
                .shadow(color: Theme.accent.opacity(0.3), radius: 20)

            Text("Scan Your Meal")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            Text("Take a photo or choose from your library to analyze the nutritional content")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            VStack(spacing: 16) {
                GradientButton(title: "Take Photo", icon: "camera.fill") { showCamera = true }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.cardSurface)
                        .foregroundStyle(Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                }
                .onChange(of: selectedPhoto) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            onImageSelected(data)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Analyzing Progress View

struct AnalyzingProgressView: View {
    let image: UIImage?
    
    var body: some View {
        VStack(spacing: 24) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black.opacity(0.4))
                    }
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Analyzing...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
            } else {
                ProgressView("Analyzing...")
            }
            
            Text("AI is detecting food items and estimating nutrition")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label("Analysis Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            HStack(spacing: 16) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Analysis Results View

struct AnalysisResultsView: View {
    let image: UIImage?
    @Binding var editableItems: [EditableAnalysisItem]
    @Binding var mealName: String
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let isSaving: Bool
    @Binding var showQuickSearch: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Captured image
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Meal name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal Name")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Enter meal name", text: $mealName)
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal)
                
                // Totals summary
                NutritionSummaryBanner(
                    calories: totalCalories,
                    protein: totalProtein,
                    carbs: totalCarbs,
                    fat: totalFat
                )
                
                // Detected items
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detected Items")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal)
                    
                    if editableItems.isEmpty {
                        ContentUnavailableView {
                            Label("No Items Detected", systemImage: "questionmark.circle")
                        } description: {
                            Text("The AI couldn't identify any food items")
                        }
                        .frame(minHeight: 150)
                    } else {
                        ForEach($editableItems) { $item in
                            AnalysisItemRow(item: $item)
                        }

                        Button { showQuickSearch = true } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Add more items from database...")
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.accentGradientStart)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Theme.cardSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .foregroundStyle(Theme.accent.opacity(0.2))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    GradientButton(
                        title: "Save Meal",
                        icon: "checkmark.circle.fill",
                        isLoading: isSaving,
                        isDisabled: editableItems.filter({ $0.isIncluded }).isEmpty,
                        action: onSave
                    )

                    Button("Cancel", action: onCancel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding()
            }
        }
        .background(Theme.background)
    }
}

// MARK: - Nutrition Summary Banner

struct NutritionSummaryBanner: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    
    var body: some View {
        HStack(spacing: 0) {
            NutritionBannerItem(value: Int(calories), label: "Cal", color: Theme.calorieValue)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(protein), label: "Protein", unit: "g", color: Theme.proteinColor)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(carbs), label: "Carbs", unit: "g", color: Theme.carbsColor)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(fat), label: "Fat", unit: "g", color: Theme.fatColor)
        }
        .padding(.vertical, 12)
        .background(Theme.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.12)))
        .padding(.horizontal)
    }
}

struct NutritionBannerItem: View {
    let value: Int
    let label: String
    var unit: String = ""
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Analysis Item Row

struct AnalysisItemRow: View {
    @Binding var item: EditableAnalysisItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Checkbox
                Button {
                    item.isIncluded.toggle()
                } label: {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.isIncluded ? Theme.successStart : Theme.textMuted)
                }

                // Food info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.item.detectedName.capitalized)
                        .font(.body)
                        .fontWeight(.medium)
                        .strikethrough(!item.isIncluded)
                        .foregroundStyle(item.isIncluded ? Theme.textPrimary : Theme.textMuted)

                    HStack(spacing: 8) {
                        Text("\(Int(item.adjustedGrams))g")
                            .foregroundStyle(Theme.textMuted)
                        Text("\(Int(item.item.calories * item.gramsMultiplier)) cal")
                            .foregroundStyle(Theme.calorieValue)
                    }
                    .font(.caption)
                }

                Spacer()
            }
            .padding()

            // PortionSelector
            if item.isIncluded {
                PortionSelector(
                    baseGrams: item.item.estimatedGrams,
                    selectedMultiplier: $item.gramsMultiplier
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Confidence indicator
            if item.isIncluded {
                HStack(spacing: 8) {
                    if !item.item.dbMatch {
                        Label("Not in database", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("AI Confidence: \(Int(item.item.confidence * 100))%")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .themedCard()
        .padding(.horizontal)
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    AnalyzeView()
}
