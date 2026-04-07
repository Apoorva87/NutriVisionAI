// GroceryCartStore — Persistent grocery cart using local SQLite.
// Items survive app restarts until explicitly cleared.

import Foundation
import SQLite3

final class GroceryCartStore {
    static let shared = GroceryCartStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.nutrivisionai.grocerystore", qos: .userInitiated)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbURL = docs.appendingPathComponent("grocery_cart.db")
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            createTable()
        }
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    private func createTable() {
        guard let db = db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS cart_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            quantity TEXT NOT NULL,
            hints TEXT DEFAULT '',
            is_custom INTEGER DEFAULT 0,
            added_at TEXT NOT NULL,
            is_checked INTEGER DEFAULT 0
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Add

    @discardableResult
    func addItem(name: String, quantity: String, hints: String = "", isCustom: Bool = false) -> Int {
        var itemId = -1
        queue.sync {
            guard let db = db else { return }

            // Dedup: skip if same name already in cart
            var checkStmt: OpaquePointer?
            let checkSQL = "SELECT COUNT(*) FROM cart_items WHERE LOWER(name) = LOWER(?);"
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStmt, 1, (name as NSString).utf8String, -1, nil)
                if sqlite3_step(checkStmt) == SQLITE_ROW && sqlite3_column_int(checkStmt, 0) > 0 {
                    sqlite3_finalize(checkStmt)
                    return
                }
            }
            sqlite3_finalize(checkStmt)

            let ts = ISO8601DateFormatter().string(from: Date())
            let sql = "INSERT INTO cart_items (name, quantity, hints, is_custom, added_at) VALUES (?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (quantity as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (hints as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, isCustom ? 1 : 0)
            sqlite3_bind_text(stmt, 5, (ts as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_DONE {
                itemId = Int(sqlite3_last_insert_rowid(db))
            }
        }
        return itemId
    }

    // MARK: - Read

    func allItems() -> [GroceryCartItem] {
        var items: [GroceryCartItem] = []
        queue.sync {
            guard let db = db else { return }
            let sql = "SELECT id, name, quantity, hints, is_custom, added_at, is_checked FROM cart_items ORDER BY id DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(GroceryCartItem(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    name: String(cString: sqlite3_column_text(stmt, 1)),
                    quantity: String(cString: sqlite3_column_text(stmt, 2)),
                    hints: String(cString: sqlite3_column_text(stmt, 3)),
                    isCustom: sqlite3_column_int(stmt, 4) == 1,
                    addedAt: String(cString: sqlite3_column_text(stmt, 5)),
                    isChecked: sqlite3_column_int(stmt, 6) == 1
                ))
            }
        }
        return items
    }

    func itemCount() -> Int {
        var count = 0
        queue.sync {
            guard let db = db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM cart_items;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW { count = Int(sqlite3_column_int(stmt, 0)) }
        }
        return count
    }

    // MARK: - Update

    func toggleChecked(id: Int) {
        queue.sync {
            guard let db = db else { return }
            let sql = "UPDATE cart_items SET is_checked = CASE WHEN is_checked = 0 THEN 1 ELSE 0 END WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(id))
            sqlite3_step(stmt)
        }
    }

    // MARK: - Delete

    func removeItem(id: Int) {
        queue.sync {
            guard let db = db else { return }
            let sql = "DELETE FROM cart_items WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(id))
            sqlite3_step(stmt)
        }
    }

    func clearAll() {
        queue.sync {
            guard let db = db else { return }
            sqlite3_exec(db, "DELETE FROM cart_items;", nil, nil, nil)
        }
    }

    func clearChecked() {
        queue.sync {
            guard let db = db else { return }
            sqlite3_exec(db, "DELETE FROM cart_items WHERE is_checked = 1;", nil, nil, nil)
        }
    }
}
