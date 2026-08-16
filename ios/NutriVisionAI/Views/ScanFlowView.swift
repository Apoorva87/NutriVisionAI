import SwiftUI
import PhotosUI

struct ScanFlowView: View {
    @EnvironmentObject private var draftStore: MealDraftStore
    @ObservedObject private var analysisService = FoodAnalysisService.shared

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var scannedBarcode: String?
    @State private var barcodeProduct: OpenFoodFactsProduct?
    @State private var showBarcodeResult = false
    @State private var isBarcodeLoading = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isAnalyzing {
                    AnalyzingProgressView(image: capturedImage)
                } else if let error = errorMessage {
                    ErrorStateView(
                        message: error,
                        onRetry: reset,
                        onCancel: reset
                    )
                } else {
                    // Capture UI
                    scanCaptureView
                }
            }
            .padding(.top, 8)
        }
        .background(Theme.background)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            if newImage != nil {
                Task { await performAnalysis() }
            }
        }
        .fullScreenCover(isPresented: $showBarcodeScanner) {
            BarcodeScannerView(scannedBarcode: $scannedBarcode)
        }
        .onChange(of: scannedBarcode) { _, newBarcode in
            guard let barcode = newBarcode else { return }
            scannedBarcode = nil
            Task { await lookupBarcode(barcode) }
        }
        .sheet(isPresented: $showBarcodeResult) {
            if let product = barcodeProduct {
                BarcodeResultSheet(product: product) { draftItem in
                    draftStore.addItem(draftItem)
                    showToast("1 item added!")
                }
            }
        }
        .overlay {
            if isBarcodeLoading {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Looking up product...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .overlay(alignment: .top) {
            if let message = toastMessage {
                toastView(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Capture View

    private var scanCaptureView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(Theme.textSecondary)
                .shadow(color: Theme.accent.opacity(0.3), radius: 20)

            Text("Scan Your Meal")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)

            Text("Take a photo or scan a barcode")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            // Side-by-side: Take Photo + Scan Barcode
            HStack(spacing: 12) {
                Button { showCamera = true } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Take Photo")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .background(Theme.accentGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if BarcodeScannerView.isAvailable {
                    Button { showBarcodeScanner = true } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                            Text("Scan Barcode")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .background(Theme.cardSurface)
                        .foregroundStyle(Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                    }
                }
            }
            .padding(.horizontal, 24)

            // Choose from Library
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
                        capturedImage = UIImage(data: data)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.successStart)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(.top, 8)
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(duration: 0.3)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                toastMessage = nil
            }
        }
    }

    // MARK: - Analysis

    private func performAnalysis() async {
        guard let image = capturedImage else { return }

        isAnalyzing = true
        errorMessage = nil

        do {
            let result = try await analysisService.analyzeImage(image)

            // Auto-add all detected items to draft
            let draftItems = result.items.map { MealDraftItem.from(analysisItem: $0) }
            draftStore.addItems(draftItems)

            // Store captured image for the draft (written to temp file, not held in memory)
            if draftStore.capturedImageURL == nil {
                draftStore.setCapturedImage(image)
            }

            let count = draftItems.count
            showToast("\(count) item\(count == 1 ? "" : "s") added!")
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false

        // Reset capture state for next photo (unless error)
        if errorMessage == nil {
            capturedImage = nil
            selectedPhoto = nil
        }
    }

    // MARK: - Barcode

    private func lookupBarcode(_ barcode: String) async {
        isBarcodeLoading = true
        defer { isBarcodeLoading = false }

        // Check local cache first
        if let cached = await LocalMealStore.shared.lookupByBarcode(barcode) {
            barcodeProduct = OpenFoodFactsProduct(
                productName: cached.foodName,
                brands: "",
                barcode: barcode,
                caloriesPer100g: cached.calories / cached.servingGrams * 100,
                proteinPer100g: cached.proteinG / cached.servingGrams * 100,
                carbsPer100g: cached.carbsG / cached.servingGrams * 100,
                fatPer100g: cached.fatG / cached.servingGrams * 100,
                servingSizeString: "\(Int(cached.servingGrams))g"
            )
            showBarcodeResult = true
            return
        }

        do {
            if let product = try await OpenFoodFactsService.shared.lookupBarcode(barcode) {
                barcodeProduct = product
                showBarcodeResult = true
            } else {
                errorMessage = "Product not found in Open Food Facts database. Try scanning a different barcode or use AI analysis."
            }
        } catch {
            errorMessage = "Barcode lookup failed: \(error.localizedDescription)"
        }
    }

    private func reset() {
        capturedImage = nil
        selectedPhoto = nil
        errorMessage = nil
        isAnalyzing = false
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
