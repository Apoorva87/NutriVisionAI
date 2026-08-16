import SwiftUI

// MARK: - Errors

enum MealDraftError: LocalizedError {
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message): return message
        }
    }
}

@MainActor
final class MealDraftStore: ObservableObject {
    static let shared = MealDraftStore()

    @Published var items: [MealDraftItem] = []
    @Published var mealName: String = ""
    @Published var isSaving: Bool = false

    /// File URL of the captured image on disk. Avoids holding a full UIImage in memory
    /// for the entire draft lifecycle (a 12MP photo can be 30–50 MB uncompressed).
    @Published private(set) var capturedImageURL: URL?

    private static let tempImageDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DraftImages")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Write the captured image to a temp file and store only the URL.
    func setCapturedImage(_ image: UIImage) {
        let url = Self.tempImageDir.appendingPathComponent("\(UUID().uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: url)
            capturedImageURL = url
        }
    }

    /// Load the image from disk on demand (for display in review sheet, etc.).
    func loadCapturedImage() -> UIImage? {
        guard let url = capturedImageURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Computed

    var isEmpty: Bool { items.isEmpty }
    var itemCount: Int { items.count }
    var includedItems: [MealDraftItem] { items.filter(\.isIncluded) }

    var totalCalories: Double { includedItems.reduce(0) { $0 + $1.totalCalories } }
    var totalProtein: Double { includedItems.reduce(0) { $0 + $1.totalProtein } }
    var totalCarbs: Double { includedItems.reduce(0) { $0 + $1.totalCarbs } }
    var totalFat: Double { includedItems.reduce(0) { $0 + $1.totalFat } }

    // MARK: - Bindings

    /// ID-based binding that is safe across removals — avoids index-out-of-bounds crashes.
    func binding(for id: UUID) -> Binding<MealDraftItem> {
        Binding(
            get: {
                // Fallback to first item if id was just removed (prevents crash during animation)
                self.items.first(where: { $0.id == id }) ?? self.items.first ?? MealDraftItem.placeholder
            },
            set: { newValue in
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index] = newValue
                }
            }
        )
    }

    // MARK: - Mutations

    func addItem(_ item: MealDraftItem) {
        items.append(item)
    }

    func addItems(_ newItems: [MealDraftItem]) {
        items.append(contentsOf: newItems)
    }

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items = []
        mealName = ""
        if let url = capturedImageURL {
            try? FileManager.default.removeItem(at: url)
        }
        capturedImageURL = nil
    }

    // MARK: - Save

    func saveMeal() async throws {
        let included = includedItems
        guard !included.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let name = mealName.isEmpty ? defaultMealName() : mealName

        if FoodAnalysisService.shared.isCloudMode {
            let analysisItems = included.map { $0.toAnalysisItem() }
            let mealId = await LocalMealStore.shared.saveMeal(
                name: name,
                image: capturedImageURL.flatMap { try? Data(contentsOf: $0) }.flatMap { UIImage(data: $0) },
                items: analysisItems
            )
            guard mealId >= 0 else {
                throw MealDraftError.saveFailed("Failed to save meal to local database")
            }
        } else {
            let mealItems = included.map { $0.toMealItemInput() }
            let request = CreateMealRequest(
                mealName: name,
                imagePath: nil,
                items: mealItems
            )
            _ = try await APIClient.shared.createMeal(request)
        }

        clear()
    }

    // MARK: - Helpers

    private func defaultMealName() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Meal at \(formatter.string(from: Date()))"
    }
}
