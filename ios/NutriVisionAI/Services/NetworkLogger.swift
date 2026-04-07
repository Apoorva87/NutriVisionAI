// NetworkLogger — Rolling log of LLM/API calls for diagnostics.
// Singleton with its own SQLite DB (network_logs.db), max 50 entries.

import Foundation
import SQLite3

final class NetworkLogger {
    static let shared = NetworkLogger()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.nutrivisionai.networklogger", qos: .utility)
    private let maxEntries = 50

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbURL = docs.appendingPathComponent("network_logs.db")
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
        CREATE TABLE IF NOT EXISTS network_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            provider TEXT NOT NULL,
            action TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'ok',
            error_message TEXT,
            response_size_bytes INTEGER
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Write (async, fire-and-forget)

    func log(provider: String, action: String, durationMs: Int, status: String,
             errorMessage: String? = nil, responseSizeBytes: Int? = nil) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let ts = ISO8601DateFormatter().string(from: Date())
            let sql = """
            INSERT INTO network_logs (timestamp, provider, action, duration_ms, status, error_message, response_size_bytes)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (provider as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (action as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, Int32(durationMs))
            sqlite3_bind_text(stmt, 5, (status as NSString).utf8String, -1, nil)
            if let err = errorMessage {
                sqlite3_bind_text(stmt, 6, (err as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let size = responseSizeBytes {
                sqlite3_bind_int(stmt, 7, Int32(size))
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_step(stmt)

            // Prune oldest entries beyond max
            let pruneSQL = "DELETE FROM network_logs WHERE id NOT IN (SELECT id FROM network_logs ORDER BY id DESC LIMIT \(self.maxEntries));"
            sqlite3_exec(db, pruneSQL, nil, nil, nil)
        }
    }

    // MARK: - Read (sync for UI consistency)

    func recentLogs(limit: Int = 50) -> [NetworkLogEntry] {
        var entries: [NetworkLogEntry] = []
        queue.sync {
            guard let db = db else { return }
            let sql = "SELECT id, timestamp, provider, action, duration_ms, status, error_message, response_size_bytes FROM network_logs ORDER BY id DESC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                let timestamp = String(cString: sqlite3_column_text(stmt, 1))
                let provider = String(cString: sqlite3_column_text(stmt, 2))
                let action = String(cString: sqlite3_column_text(stmt, 3))
                let durationMs = Int(sqlite3_column_int(stmt, 4))
                let status = String(cString: sqlite3_column_text(stmt, 5))
                let errorMessage = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
                let responseSizeBytes: Int? = sqlite3_column_type(stmt, 7) != SQLITE_NULL
                    ? Int(sqlite3_column_int(stmt, 7)) : nil

                entries.append(NetworkLogEntry(
                    id: id,
                    timestamp: timestamp,
                    provider: provider,
                    action: action,
                    durationMs: durationMs,
                    status: status,
                    errorMessage: errorMessage,
                    responseSizeBytes: responseSizeBytes
                ))
            }
        }
        return entries
    }

    func entryCount() -> Int {
        var count = 0
        queue.sync {
            guard let db = db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM network_logs;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        return count
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            sqlite3_exec(db, "DELETE FROM network_logs;", nil, nil, nil)
        }
    }
}
