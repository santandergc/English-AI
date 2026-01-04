import Foundation
import SQLite3

struct RecordStatistics {
    let totalRecords: Int
    let keyboardCount: Int
    let wisprCount: Int
    let totalCharacters: Int
}

final class DatabaseService {
    static let shared = DatabaseService()

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.englishai.database", qos: .userInitiated)

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private func getDatabasePath() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("EnglishAI", isDirectory: true)

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        return appDirectory.appendingPathComponent("records.sqlite").path
    }

    private func openDatabase() {
        let dbPath = getDatabasePath()

            if sqlite3_open(dbPath, &db) != SQLITE_OK {
                return
            }

        // Enable WAL mode for better concurrent access
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func createTables() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            source TEXT NOT NULL CHECK(source IN ('keyboard', 'wispr')),
            content TEXT NOT NULL,
            active_app TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_records_timestamp ON records(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_records_source ON records(source);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTableSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("Error creating table: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    func insertRecord(_ record: Record) {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            // Use IMMEDIATE transaction to prevent race conditions
            // This ensures only one insert can happen at a time
            let beginTransactionSQL = "BEGIN IMMEDIATE TRANSACTION;"
            var errMsg: UnsafeMutablePointer<CChar>?
            
            if sqlite3_exec(db, beginTransactionSQL, nil, nil, &errMsg) != SQLITE_OK {
                if let errMsg = errMsg {
                    sqlite3_free(errMsg)
                }
                return
            }
            
            defer {
                // Always commit or rollback the transaction
                if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
                    sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                }
            }
            
            // First check if a duplicate exists (within transaction)
            // Check if EXACT same content exists within the last 60 seconds
            let checkSQL = """
            SELECT COUNT(*) FROM records
            WHERE content = ?
            AND timestamp > ?;
            """
            
            var stmt: OpaquePointer?
            var hasDuplicate = false
            
            if sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, record.content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                
                // Check for duplicates within last 60 seconds
                let cutoffTime = record.timestamp.timeIntervalSince1970 - 60.0
                sqlite3_bind_double(stmt, 2, cutoffTime)
                
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = sqlite3_column_int(stmt, 0)
                    hasDuplicate = count > 0
                }
            }
            sqlite3_finalize(stmt)
            
            // If duplicate exists, skip insert
            if hasDuplicate {
                return
            }

            // No duplicate found, proceed with insert
            let insertSQL = "INSERT INTO records (timestamp, source, content, active_app) VALUES (?, ?, ?, ?);"

            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, record.timestamp.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 2, record.source.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, record.content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, record.activeApp, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("Error inserting record: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }
    }

    func fetchRecords(limit: Int = 100, offset: Int = 0) -> [Record] {
        var records: [Record] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT id, timestamp, source, content, active_app FROM records ORDER BY timestamp DESC LIMIT ? OFFSET ?;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                sqlite3_bind_int(stmt, 2, Int32(offset))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                    let sourceRaw = String(cString: sqlite3_column_text(stmt, 2))
                    let content = String(cString: sqlite3_column_text(stmt, 3))
                    let activeApp = String(cString: sqlite3_column_text(stmt, 4))

                    let source = RecordSource(rawValue: sourceRaw) ?? .keyboard

                    let record = Record(id: id, timestamp: timestamp, source: source, content: content, activeApp: activeApp)
                    records.append(record)
                }
            }
            sqlite3_finalize(stmt)
        }

        return records
    }

    func getStatistics() -> RecordStatistics {
        var stats = RecordStatistics(totalRecords: 0, keyboardCount: 0, wisprCount: 0, totalCharacters: 0)

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            // Total records
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records;", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let total = Int(sqlite3_column_int(stmt, 0))
                    stats = RecordStatistics(totalRecords: total, keyboardCount: stats.keyboardCount, wisprCount: stats.wisprCount, totalCharacters: stats.totalCharacters)
                }
            }
            sqlite3_finalize(stmt)

            // Keyboard count
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records WHERE source = 'keyboard';", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmt, 0))
                    stats = RecordStatistics(totalRecords: stats.totalRecords, keyboardCount: count, wisprCount: stats.wisprCount, totalCharacters: stats.totalCharacters)
                }
            }
            sqlite3_finalize(stmt)

            // Wispr count
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records WHERE source = 'wispr';", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmt, 0))
                    stats = RecordStatistics(totalRecords: stats.totalRecords, keyboardCount: stats.keyboardCount, wisprCount: count, totalCharacters: stats.totalCharacters)
                }
            }
            sqlite3_finalize(stmt)

            // Total characters
            if sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(LENGTH(content)), 0) FROM records;", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let chars = Int(sqlite3_column_int(stmt, 0))
                    stats = RecordStatistics(totalRecords: stats.totalRecords, keyboardCount: stats.keyboardCount, wisprCount: stats.wisprCount, totalCharacters: chars)
                }
            }
            sqlite3_finalize(stmt)
        }

        return stats
    }

    func deleteAllRecords() {
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            sqlite3_exec(db, "DELETE FROM records;", nil, nil, nil)
        }
    }
    
    /// Remove duplicate records, keeping only the most recent one
    func removeDuplicateRecords() {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let deleteSQL = """
            DELETE FROM records
            WHERE id NOT IN (
                SELECT MAX(id)
                FROM records
                GROUP BY content
            );
            """
            
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, deleteSQL, nil, nil, &errMsg) != SQLITE_OK {
                if let errMsg = errMsg {
                    sqlite3_free(errMsg)
                }
            } else {
                let changes = sqlite3_changes(db)
                if changes > 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("DatabaseDidChange"), object: nil)
                    }
                }
            }
        }
    }
    
}
