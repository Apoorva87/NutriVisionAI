// NutritionDB — Local SQLite wrapper for the bundled nutrition database.
// Uses the sqlite3 C API directly (available on iOS without dependencies).

import Foundation
import SQLite3

final class NutritionDB {
    static let shared = NutritionDB()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.nutrivisionai.nutritiondb", qos: .userInitiated)

    private init() {
        openDatabase()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbURL = documentsURL.appendingPathComponent("nutrition.db")

        // Copy from bundle if not in Documents yet
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            guard let bundledURL = Bundle.main.url(forResource: "nutrition", withExtension: "db", subdirectory: "Data") else {
                // Try without subdirectory (XcodeGen may flatten)
                guard let flatURL = Bundle.main.url(forResource: "nutrition", withExtension: "db") else {
                    print("NutritionDB: bundled nutrition.db not found")
                    return
                }
                try? FileManager.default.copyItem(at: flatURL, to: dbURL)
                openAt(dbURL)
                return
            }
            try? FileManager.default.copyItem(at: bundledURL, to: dbURL)
        }
        openAt(dbURL)
    }

    private func openAt(_ url: URL) {
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("NutritionDB: failed to open \(url.path)")
            db = nil
        }
    }

    // MARK: - Search

    func search(query: String, limit: Int = 15) -> [FoodItem] {
        guard let db = db else { return [] }
        var results: [FoodItem] = []

        queue.sync {
            let sql = "SELECT canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g, source_label FROM nutrition_items WHERE canonical_name LIKE ? ORDER BY canonical_name LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let pattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(stmt, 0))
                let servingGrams = sqlite3_column_double(stmt, 1)
                let calories = sqlite3_column_double(stmt, 2)
                let proteinG = sqlite3_column_double(stmt, 3)
                let carbsG = sqlite3_column_double(stmt, 4)
                let fatG = sqlite3_column_double(stmt, 5)
                let sourceLabel = sqlite3_column_text(stmt, 6).map { String(cString: $0) }

                results.append(FoodItem(
                    canonicalName: name,
                    servingGrams: servingGrams,
                    calories: calories,
                    proteinG: proteinG,
                    carbsG: carbsG,
                    fatG: fatG,
                    sourceLabel: sourceLabel
                ))
            }
        }
        return results
    }

    // MARK: - Lookup

    func lookup(canonicalName: String, grams: Double) -> LocalNutritionInfo? {
        guard let db = db else { return nil }
        var result: LocalNutritionInfo?

        queue.sync {
            // Try direct lookup first
            let resolved = resolveAliasSync(canonicalName)
            let sql = "SELECT canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g, COALESCE(source_label, '') FROM nutrition_items WHERE canonical_name = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (resolved as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(stmt) == SQLITE_ROW else { return }

            let name = String(cString: sqlite3_column_text(stmt, 0))
            let servingGrams = sqlite3_column_double(stmt, 1)
            let baseCal = sqlite3_column_double(stmt, 2)
            let basePro = sqlite3_column_double(stmt, 3)
            let baseCarb = sqlite3_column_double(stmt, 4)
            let baseFat = sqlite3_column_double(stmt, 5)
            let source = String(cString: sqlite3_column_text(stmt, 6))

            // Scale nutrition by gram amount
            let scale = servingGrams > 0 ? grams / servingGrams : 1.0
            result = LocalNutritionInfo(
                canonicalName: name,
                servingGrams: grams,
                calories: baseCal * scale,
                proteinG: basePro * scale,
                carbsG: baseCarb * scale,
                fatG: baseFat * scale,
                sourceLabel: source
            )
        }
        return result
    }

    // MARK: - Alias Resolution

    func resolveAlias(_ name: String) -> String {
        guard db != nil else { return name }
        var result = name
        queue.sync {
            result = resolveAliasSync(name)
        }
        return result
    }

    private func resolveAliasSync(_ name: String) -> String {
        guard let db = db else { return name }
        let sql = "SELECT canonical_name FROM nutrition_aliases WHERE alias = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return name }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (name.lowercased() as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return name }
        return String(cString: sqlite3_column_text(stmt, 0))
    }
}
