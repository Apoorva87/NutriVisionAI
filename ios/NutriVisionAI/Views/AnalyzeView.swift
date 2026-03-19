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
    
    private var totalCalories: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.calories }
    }
    
    private var totalProtein: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.proteinG }
    }
    
    private var totalCarbs: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.carbsG }
    }
    
    private var totalFat: Double {
        editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.fatG }
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
        guard let result = analysisResult else { return }
        
        let includedItems = editableItems
            .filter { $0.isIncluded }
            .map { editable -> MealItemInput in
                MealItemInput(
                    detectedName: editable.item.detectedName,
                    canonicalName: editable.item.canonicalName,
                    portionLabel: editable.item.portionLabel,
                    estimatedGrams: editable.adjustedGrams,
                    uncertainty: editable.item.uncertainty,
                    confidence: editable.item.confidence
                )
            }
        
        guard !includedItems.isEmpty else {
            errorMessage = "Please include at least one item"
            return
        }
        
        isSaving = true
        
        Task {
            do {
                let request = CreateMealRequest(
                    mealName: mealName.isEmpty ? "Scanned Meal" : mealName,
                    imagePath: result.imagePath,
                    items: includedItems
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
                .foregroundStyle(.secondary)
            
            Text("Scan Your Meal")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Take a photo or choose from your library to analyze the nutritional content")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    TextField("Enter meal name", text: $mealName)
                        .textFieldStyle(.roundedBorder)
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
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onSave) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("Save Meal", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(editableItems.filter({ $0.isIncluded }).isEmpty ? Color.gray : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(isSaving || editableItems.filter({ $0.isIncluded }).isEmpty)
                    
                    Button("Cancel", action: onCancel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
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
            NutritionBannerItem(value: Int(calories), label: "Cal", color: .green)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(protein), label: "Protein", unit: "g", color: .blue)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(carbs), label: "Carbs", unit: "g", color: .orange)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(fat), label: "Fat", unit: "g", color: .purple)
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Analysis Item Row

struct AnalysisItemRow: View {
    @Binding var item: EditableAnalysisItem
    
    private let portionOptions = [
        ("0.5x", 0.5),
        ("1x", 1.0),
        ("1.5x", 1.5),
        ("2x", 2.0)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Checkbox
                Button {
                    item.isIncluded.toggle()
                } label: {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.isIncluded ? .green : .secondary)
                }
                
                // Food info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.item.detectedName.capitalized)
                        .font(.body)
                        .fontWeight(.medium)
                        .strikethrough(!item.isIncluded)
                        .foregroundStyle(item.isIncluded ? .primary : .secondary)
                    
                    HStack(spacing: 8) {
                        Text("\(Int(item.adjustedGrams))g")
                        Text("\(Int(item.item.calories * item.gramsMultiplier)) cal")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                
                Spacer()
                
                // Portion selector
                if item.isIncluded {
                    Menu {
                        ForEach(portionOptions, id: \.0) { option in
                            Button {
                                item.gramsMultiplier = option.1
                            } label: {
                                HStack {
                                    Text(option.0)
                                    if item.gramsMultiplier == option.1 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(portionOptions.first { $0.1 == item.gramsMultiplier }?.0 ?? "1x")
                                .font(.subheadline)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
            
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
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
