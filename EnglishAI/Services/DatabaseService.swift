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
        
        CREATE TABLE IF NOT EXISTS insights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date_range_start REAL NOT NULL,
            date_range_end REAL NOT NULL,
            insight_type TEXT NOT NULL,
            content TEXT NOT NULL,
            record_count INTEGER NOT NULL,
            character_count INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_insights_date ON insights(date_range_start DESC);
        CREATE INDEX IF NOT EXISTS idx_insights_type ON insights(insight_type);
        
        CREATE TABLE IF NOT EXISTS analysis_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            analyzed_at REAL NOT NULL,
            date_range_start REAL NOT NULL,
            date_range_end REAL NOT NULL,
            records_analyzed INTEGER NOT NULL,
            characters_analyzed INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_analysis_sessions_date ON analysis_sessions(analyzed_at DESC);
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
            var recordInserted = false

            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, record.timestamp.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 2, record.source.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, record.content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, record.activeApp, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(stmt) == SQLITE_DONE {
                    recordInserted = true
                } else {
                    print("Error inserting record: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
            
            // Notify UI to refresh if a record was successfully inserted
            if recordInserted {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("DatabaseDidChange"), object: nil)
                }
            }
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
    
    /// Fetch all unique dates that have records (grouped by day)
    func fetchAllUniqueDates() -> [Date] {
        var dates: [Date] = []
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            // Get all unique dates by grouping timestamps by day
            // We use strftime to extract date part and group by it, then get min timestamp for each day
            // This is more efficient than fetching all timestamps
            let querySQL = """
                SELECT MIN(timestamp) as day_start_timestamp
                FROM records
                GROUP BY strftime('%Y-%m-%d', timestamp, 'unixepoch', 'localtime')
                ORDER BY day_start_timestamp DESC;
            """
            
            var stmt: OpaquePointer?
            let calendar = Calendar.current
            
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                    let dayStart = calendar.startOfDay(for: timestamp)
                    dates.append(dayStart)
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return dates
    }
    
    /// Fetch records for a specific date (day)
    func fetchRecords(for date: Date) -> [Record] {
        var records: [Record] = []
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let startTimestamp = dayStart.timeIntervalSince1970
            let endTimestamp = dayEnd.timeIntervalSince1970
            
            let querySQL = """
                SELECT id, timestamp, source, content, active_app 
                FROM records 
                WHERE timestamp >= ? AND timestamp < ?
                ORDER BY timestamp DESC;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, startTimestamp)
                sqlite3_bind_double(stmt, 2, endTimestamp)
                
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
    
    /// Get record count for a specific date
    func getRecordCount(for date: Date) -> Int {
        var count = 0
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let startTimestamp = dayStart.timeIntervalSince1970
            let endTimestamp = dayEnd.timeIntervalSince1970
            
            let querySQL = """
                SELECT COUNT(*) 
                FROM records 
                WHERE timestamp >= ? AND timestamp < ?;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, startTimestamp)
                sqlite3_bind_double(stmt, 2, endTimestamp)
                
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return count
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
    
    // MARK: - Insights
    
    func deleteInsights(for date: Date) {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let deleteSQL = """
            DELETE FROM insights
            WHERE date_range_start >= ? AND date_range_start < ?;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, dayStart.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, dayEnd.timeIntervalSince1970)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("Error deleting insights: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
            
            // Also delete analysis sessions for this date
            let deleteSessionSQL = """
            DELETE FROM analysis_sessions
            WHERE date_range_start >= ? AND date_range_start < ?;
            """
            
            if sqlite3_prepare_v2(db, deleteSessionSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, dayStart.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, dayEnd.timeIntervalSince1970)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("Error deleting analysis sessions: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func insertInsight(_ insight: Insight) {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let insertSQL = """
            INSERT INTO insights (date_range_start, date_range_end, insight_type, content, record_count, character_count, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, insight.dateRangeStart.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, insight.dateRangeEnd.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 3, insight.insightType.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, insight.content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 5, Int32(insight.recordCount))
                sqlite3_bind_int(stmt, 6, Int32(insight.characterCount))
                sqlite3_bind_double(stmt, 7, insight.createdAt.timeIntervalSince1970)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("Error inserting insight: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func fetchInsights(for date: Date) -> [Insight] {
        var insights: [Insight] = []
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let querySQL = """
            SELECT id, date_range_start, date_range_end, insight_type, content, record_count, character_count, created_at
            FROM insights
            WHERE date_range_start >= ? AND date_range_start < ?
            ORDER BY created_at DESC;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, dayStart.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, dayEnd.timeIntervalSince1970)
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    let dateRangeStart = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                    let dateRangeEnd = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                    let typeRaw = String(cString: sqlite3_column_text(stmt, 3))
                    let content = String(cString: sqlite3_column_text(stmt, 4))
                    let recordCount = Int(sqlite3_column_int(stmt, 5))
                    let characterCount = Int(sqlite3_column_int(stmt, 6))
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
                    
                    let insightType = InsightType(rawValue: typeRaw) ?? .grammar
                    
                    let insight = Insight(
                        id: id,
                        dateRangeStart: dateRangeStart,
                        dateRangeEnd: dateRangeEnd,
                        insightType: insightType,
                        content: content,
                        recordCount: recordCount,
                        characterCount: characterCount,
                        createdAt: createdAt
                    )
                    insights.append(insight)
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return insights
    }
    
    func fetchAllInsights(limit: Int = 100) -> [Insight] {
        var insights: [Insight] = []
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let querySQL = """
            SELECT id, date_range_start, date_range_end, insight_type, content, record_count, character_count, created_at
            FROM insights
            ORDER BY created_at DESC
            LIMIT ?;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmt, 0)
                    let dateRangeStart = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                    let dateRangeEnd = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                    let typeRaw = String(cString: sqlite3_column_text(stmt, 3))
                    let content = String(cString: sqlite3_column_text(stmt, 4))
                    let recordCount = Int(sqlite3_column_int(stmt, 5))
                    let characterCount = Int(sqlite3_column_int(stmt, 6))
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
                    
                    let insightType = InsightType(rawValue: typeRaw) ?? .grammar
                    
                    let insight = Insight(
                        id: id,
                        dateRangeStart: dateRangeStart,
                        dateRangeEnd: dateRangeEnd,
                        insightType: insightType,
                        content: content,
                        recordCount: recordCount,
                        characterCount: characterCount,
                        createdAt: createdAt
                    )
                    insights.append(insight)
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return insights
    }
    
    // MARK: - Analysis Sessions
    
    func insertAnalysisSession(_ session: AnalysisSession) {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let insertSQL = """
            INSERT INTO analysis_sessions (analyzed_at, date_range_start, date_range_end, records_analyzed, characters_analyzed)
            VALUES (?, ?, ?, ?, ?);
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, session.analyzedAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, session.dateRangeStart.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 3, session.dateRangeEnd.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 4, Int32(session.recordsAnalyzed))
                sqlite3_bind_int(stmt, 5, Int32(session.charactersAnalyzed))
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("Error inserting analysis session: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func getLastAnalysisDate() -> Date? {
        var lastDate: Date?
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let querySQL = "SELECT MAX(date_range_end) FROM analysis_sessions;"
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                    lastDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return lastDate
    }
    
    func hasAnalysis(for date: Date) -> Bool {
        var hasAnalysis = false
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            // Use same logic as fetchInsights: check if date_range_start is within the day
            let querySQL = """
            SELECT COUNT(*) FROM analysis_sessions
            WHERE date_range_start >= ? AND date_range_start < ?;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, dayStart.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, dayEnd.timeIntervalSince1970)
                
                if sqlite3_step(stmt) == SQLITE_ROW {
                    hasAnalysis = sqlite3_column_int(stmt, 0) > 0
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return hasAnalysis
    }
    
    func fetchUnanalyzedRecords(minCharacters: Int = 300) -> (records: [Record], dateRange: (start: Date, end: Date)?) {
        var records: [Record] = []
        var dateRange: (start: Date, end: Date)?
        
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            // Get the last analysis end date
            let lastAnalysisDate = self.getLastAnalysisDate()
            
            var querySQL: String
            var stmt: OpaquePointer?
            
            if let lastDate = lastAnalysisDate {
                querySQL = """
                SELECT id, timestamp, source, content, active_app
                FROM records
                WHERE timestamp > ?
                ORDER BY timestamp ASC;
                """
                
                if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_double(stmt, 1, lastDate.timeIntervalSince1970)
                }
            } else {
                querySQL = """
                SELECT id, timestamp, source, content, active_app
                FROM records
                ORDER BY timestamp ASC;
                """
                
                _ = sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil)
            }
            
            if stmt != nil {
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
            
            if !records.isEmpty {
                let startDate = records.first!.timestamp
                let endDate = records.last!.timestamp
                dateRange = (start: startDate, end: endDate)
            }
        }
        
        return (records, dateRange)
    }
    
}
