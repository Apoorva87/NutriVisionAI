// LocalMealStore — Local SQLite persistence for meals in cloud mode.
// Stores meals and items locally when not using the backend.

import Foundation
import SQLite3
import UIKit


final class LocalMealStore {
    static let shared = LocalMealStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.nutrivisionai.mealstore", qos: .userInitiated)
    private let imagesDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        imagesDir = docs.appendingPathComponent("MealImages")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let dbURL = docs.appendingPathComponent("meals.db")
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            createTables()
        }
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    private func createTables() {
        guard let db = db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meal_name TEXT NOT NULL,
            image_path TEXT,
            total_calories REAL DEFAULT 0,
            total_protein_g REAL DEFAULT 0,
            total_carbs_g REAL DEFAULT 0,
            total_fat_g REAL DEFAULT 0,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS meal_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meal_id INTEGER NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
            detected_name TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            portion_label TEXT,
            estimated_grams REAL,
            calories REAL,
            protein_g REAL,
            carbs_g REAL,
            fat_g REAL,
            confidence REAL
        );
        CREATE TABLE IF NOT EXISTS custom_foods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            food_name TEXT NOT NULL UNIQUE,
            serving_grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            created_at TEXT NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        migrateAddBarcodeColumn()
    }

    /// Add barcode column to custom_foods if it doesn't exist yet.
    private func migrateAddBarcodeColumn() {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        var hasBarcode = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(custom_foods);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1), String(cString: name) == "barcode" {
                    hasBarcode = true
                    break
                }
            }
            sqlite3_finalize(stmt)
        }
        if !hasBarcode {
            sqlite3_exec(db, "ALTER TABLE custom_foods ADD COLUMN barcode TEXT;", nil, nil, nil)
        }
    }

    // MARK: - Save

    func saveMeal(name: String, image: UIImage?, items: [AnalysisItem]) -> Int {
        guard let db = db else { return -1 }
        var mealId: Int = -1

        queue.sync {
            // Save image to disk if provided
            var imagePath: String? = nil
            if let image = image {
                // Save a small thumbnail (max 256px) to minimize storage
                let thumbnail = Self.resizeImage(image, maxDimension: 256)
                if let data = thumbnail.jpegData(compressionQuality: 0.4) {
                    let filename = "\(UUID().uuidString).jpg"
                    let fileURL = imagesDir.appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                    imagePath = filename
                }
            }

            // Calculate totals
            let totalCal = items.reduce(0.0) { $0 + $1.calories }
            let totalPro = items.reduce(0.0) { $0 + $1.proteinG }
            let totalCarb = items.reduce(0.0) { $0 + $1.carbsG }
            let totalFat = items.reduce(0.0) { $0 + $1.fatG }
            let now = ISO8601DateFormatter().string(from: Date())

            let insertMeal = "INSERT INTO meals (meal_name, image_path, total_calories, total_protein_g, total_carbs_g, total_fat_g, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertMeal, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, transient)
            if let ip = imagePath {
                sqlite3_bind_text(stmt, 2, (ip as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_double(stmt, 3, totalCal)
            sqlite3_bind_double(stmt, 4, totalPro)
            sqlite3_bind_double(stmt, 5, totalCarb)
            sqlite3_bind_double(stmt, 6, totalFat)
            sqlite3_bind_text(stmt, 7, (now as NSString).utf8String, -1, transient)

            guard sqlite3_step(stmt) == SQLITE_DONE else { return }
            mealId = Int(sqlite3_last_insert_rowid(db))

            // Insert items
            for item in items {
                let insertItem = "INSERT INTO meal_items (meal_id, detected_name, canonical_name, portion_label, estimated_grams, calories, protein_g, carbs_g, fat_g, confidence) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                var itemStmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, insertItem, -1, &itemStmt, nil) == SQLITE_OK else { continue }
                sqlite3_bind_int(itemStmt, 1, Int32(mealId))
                sqlite3_bind_text(itemStmt, 2, (item.detectedName as NSString).utf8String, -1, transient)
                sqlite3_bind_text(itemStmt, 3, (item.canonicalName as NSString).utf8String, -1, transient)
                sqlite3_bind_text(itemStmt, 4, (item.portionLabel as NSString).utf8String, -1, transient)
                sqlite3_bind_double(itemStmt, 5, item.estimatedGrams)
                sqlite3_bind_double(itemStmt, 6, item.calories)
                sqlite3_bind_double(itemStmt, 7, item.proteinG)
                sqlite3_bind_double(itemStmt, 8, item.carbsG)
                sqlite3_bind_double(itemStmt, 9, item.fatG)
                sqlite3_bind_double(itemStmt, 10, item.confidence)
                sqlite3_step(itemStmt)
                sqlite3_finalize(itemStmt)
            }
        }
        return mealId
    }

    // MARK: - Delete

    func deleteMeal(id: Int) {
        guard let db = db else { return }
        queue.sync {
            // Delete image file
            let selectImg = "SELECT image_path FROM meals WHERE id = ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectImg, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(id))
                if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                    let filename = String(cString: cStr)
                    let fileURL = imagesDir.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                sqlite3_finalize(stmt)
            }

            let deleteSql = "DELETE FROM meals WHERE id = ?"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(delStmt, 1, Int32(id))
                sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
        }
    }

    // MARK: - Recent Meals

    func recentMeals(limit: Int = 10) -> [MealRecord] {
        guard let db = db else { return [] }
        var meals: [MealRecord] = []
        let today = AppTimeZone.todayString()
        let offset = AppTimeZone.sqliteOffsetModifier()

        queue.sync {
            let sql = "SELECT id, meal_name, image_path, created_at, total_calories, total_protein_g, total_carbs_g, total_fat_g FROM meals WHERE date(created_at, '\(offset)') = ? ORDER BY created_at DESC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (today as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let imgPath = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let createdAt = String(cString: sqlite3_column_text(stmt, 3))
                let cal = sqlite3_column_double(stmt, 4)
                let pro = sqlite3_column_double(stmt, 5)
                let carb = sqlite3_column_double(stmt, 6)
                let fat = sqlite3_column_double(stmt, 7)

                meals.append(MealRecord(
                    id: id, mealName: name, imagePath: imgPath,
                    createdAt: createdAt, totalCalories: cal,
                    totalProteinG: pro, totalCarbsG: carb, totalFatG: fat
                ))
            }
        }
        return meals
    }

    // MARK: - Today Summary

    func todaySummary() -> DashboardSummary {
        guard let db = db else { return emptyDashboard() }
        var cal = 0.0, pro = 0.0, carb = 0.0, fat = 0.0
        let today = AppTimeZone.todayString()
        let offset = AppTimeZone.sqliteOffsetModifier()

        queue.sync {
            let sql = "SELECT COALESCE(SUM(total_calories), 0), COALESCE(SUM(total_protein_g), 0), COALESCE(SUM(total_carbs_g), 0), COALESCE(SUM(total_fat_g), 0) FROM meals WHERE date(created_at, '\(offset)') = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (today as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return }
            cal = sqlite3_column_double(stmt, 0)
            pro = sqlite3_column_double(stmt, 1)
            carb = sqlite3_column_double(stmt, 2)
            fat = sqlite3_column_double(stmt, 3)
        }

        let calorieGoal = UserDefaults.standard.integer(forKey: "local_calorie_goal").nonZero ?? 2200
        let proteinGoal = UserDefaults.standard.integer(forKey: "local_protein_goal").nonZero ?? 150
        let carbsGoal = UserDefaults.standard.integer(forKey: "local_carbs_goal").nonZero ?? 200
        let fatGoal = UserDefaults.standard.integer(forKey: "local_fat_goal").nonZero ?? 65

        return DashboardSummary(
            calories: cal, proteinG: pro, carbsG: carb, fatG: fat,
            calorieGoal: calorieGoal,
            remainingCalories: Double(calorieGoal) - cal,
            macroGoals: MacroGoals(proteinG: proteinGoal, carbsG: carbsGoal, fatG: fatGoal)
        )
    }

    private func emptyDashboard() -> DashboardSummary {
        DashboardSummary(
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0,
            calorieGoal: 2200, remainingCalories: 2200,
            macroGoals: MacroGoals(proteinG: 150, carbsG: 200, fatG: 65)
        )
    }

    // MARK: - History

    func history(days: Int = 14) -> HistoryResponse {
        guard let db = db else {
            return HistoryResponse(trends: [], groupedMeals: [:], topFoods: [])
        }

        var trends: [[String: AnyCodableValue]] = []
        var groupedMeals: [String: [MealRecord]] = [:]
        var topFoods: [[String: AnyCodableValue]] = []
        let offset = AppTimeZone.sqliteOffsetModifier()
        let cutoff = AppTimeZone.formatDate(Date().addingTimeInterval(-Double(days) * 86400))

        queue.sync {
            // Trends: daily sums (group by local date)
            let trendsSql = "SELECT date(created_at, '\(offset)') as day, SUM(total_calories), SUM(total_protein_g), SUM(total_carbs_g), SUM(total_fat_g) FROM meals WHERE date(created_at, '\(offset)') >= ? GROUP BY date(created_at, '\(offset)') ORDER BY day"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, trendsSql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, (cutoff as NSString).utf8String, -1, nil)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let day = String(cString: sqlite3_column_text(stmt, 0))
                    trends.append([
                        "date": AnyCodableValue.string(day),
                        "calories": AnyCodableValue.double(sqlite3_column_double(stmt, 1)),
                        "protein_g": AnyCodableValue.double(sqlite3_column_double(stmt, 2)),
                        "carbs_g": AnyCodableValue.double(sqlite3_column_double(stmt, 3)),
                        "fat_g": AnyCodableValue.double(sqlite3_column_double(stmt, 4))
                    ])
                }
            }

            // Grouped meals: all meals in range, grouped by local date
            let mealsSql = "SELECT id, meal_name, image_path, created_at, total_calories, total_protein_g, total_carbs_g, total_fat_g FROM meals WHERE date(created_at, '\(offset)') >= ? ORDER BY created_at DESC"
            var mealStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, mealsSql, -1, &mealStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(mealStmt) }
                sqlite3_bind_text(mealStmt, 1, (cutoff as NSString).utf8String, -1, nil)
                while sqlite3_step(mealStmt) == SQLITE_ROW {
                    let mealId = Int(sqlite3_column_int(mealStmt, 0))
                    let name = String(cString: sqlite3_column_text(mealStmt, 1))
                    let imgPath = sqlite3_column_text(mealStmt, 2).map { String(cString: $0) }
                    let createdAt = String(cString: sqlite3_column_text(mealStmt, 3))
                    let meal = MealRecord(
                        id: mealId, mealName: name, imagePath: imgPath,
                        createdAt: createdAt, totalCalories: sqlite3_column_double(mealStmt, 4),
                        totalProteinG: sqlite3_column_double(mealStmt, 5),
                        totalCarbsG: sqlite3_column_double(mealStmt, 6),
                        totalFatG: sqlite3_column_double(mealStmt, 7)
                    )
                    let dayKey = AppTimeZone.localDateString(from: createdAt)
                    groupedMeals[dayKey, default: []].append(meal)
                }
            }

            // Top foods
            let topSql = "SELECT canonical_name, COUNT(*) as cnt, SUM(calories) as total_cal FROM meal_items mi JOIN meals m ON mi.meal_id = m.id WHERE date(m.created_at, '\(offset)') >= ? GROUP BY canonical_name ORDER BY cnt DESC LIMIT 10"
            var topStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, topSql, -1, &topStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(topStmt) }
                sqlite3_bind_text(topStmt, 1, (cutoff as NSString).utf8String, -1, nil)
                while sqlite3_step(topStmt) == SQLITE_ROW {
                    let foodName = String(cString: sqlite3_column_text(topStmt, 0))
                    topFoods.append([
                        "canonical_name": AnyCodableValue.string(foodName),
                        "count": AnyCodableValue.int(Int(sqlite3_column_int(topStmt, 1))),
                        "total_calories": AnyCodableValue.double(sqlite3_column_double(topStmt, 2))
                    ])
                }
            }
        }

        return HistoryResponse(trends: trends, groupedMeals: groupedMeals, topFoods: topFoods)
    }

    // MARK: - Custom Foods

    @discardableResult
    func saveCustomFood(name: String, servingGrams: Double, calories: Double,
                        proteinG: Double, carbsG: Double, fatG: Double,
                        barcode: String? = nil) -> Int {
        guard let db = db else { return -1 }
        var foodId = -1
        queue.sync {
            let now = ISO8601DateFormatter().string(from: Date())
            let sql = "INSERT OR REPLACE INTO custom_foods (food_name, serving_grams, calories, protein_g, carbs_g, fat_g, created_at, barcode) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, transient)
            sqlite3_bind_double(stmt, 2, servingGrams)
            sqlite3_bind_double(stmt, 3, calories)
            sqlite3_bind_double(stmt, 4, proteinG)
            sqlite3_bind_double(stmt, 5, carbsG)
            sqlite3_bind_double(stmt, 6, fatG)
            sqlite3_bind_text(stmt, 7, (now as NSString).utf8String, -1, transient)
            if let bc = barcode {
                sqlite3_bind_text(stmt, 8, (bc as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            if sqlite3_step(stmt) == SQLITE_DONE {
                foodId = Int(sqlite3_last_insert_rowid(db))
            }
        }
        return foodId
    }

    func lookupByBarcode(_ barcode: String) -> CustomFood? {
        guard let db = db else { return nil }
        var result: CustomFood?
        queue.sync {
            let sql = "SELECT id, food_name, serving_grams, calories, protein_g, carbs_g, fat_g, barcode FROM custom_foods WHERE barcode = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (barcode as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = CustomFood(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    foodName: String(cString: sqlite3_column_text(stmt, 1)),
                    servingGrams: sqlite3_column_double(stmt, 2),
                    calories: sqlite3_column_double(stmt, 3),
                    proteinG: sqlite3_column_double(stmt, 4),
                    carbsG: sqlite3_column_double(stmt, 5),
                    fatG: sqlite3_column_double(stmt, 6),
                    barcode: sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                )
            }
        }
        return result
    }

    func allCustomFoods() -> [CustomFood] {
        guard let db = db else { return [] }
        var foods: [CustomFood] = []
        queue.sync {
            let sql = "SELECT id, food_name, serving_grams, calories, protein_g, carbs_g, fat_g, barcode FROM custom_foods ORDER BY food_name"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                foods.append(CustomFood(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    foodName: String(cString: sqlite3_column_text(stmt, 1)),
                    servingGrams: sqlite3_column_double(stmt, 2),
                    calories: sqlite3_column_double(stmt, 3),
                    proteinG: sqlite3_column_double(stmt, 4),
                    carbsG: sqlite3_column_double(stmt, 5),
                    fatG: sqlite3_column_double(stmt, 6),
                    barcode: sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                ))
            }
        }
        return foods
    }

    func deleteCustomFood(id: Int) {
        guard let db = db else { return }
        queue.sync {
            let sql = "DELETE FROM custom_foods WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(id))
            sqlite3_step(stmt)
        }
    }
}

// MARK: - Helpers

extension LocalMealStore {
    static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
