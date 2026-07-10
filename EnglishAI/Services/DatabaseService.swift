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
        createFocusTablesWithBackup()
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

        CREATE TABLE IF NOT EXISTS recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            duration REAL NOT NULL,
            audio_file_path TEXT,
            transcription TEXT,
            transcription_status TEXT NOT NULL DEFAULT 'pending' CHECK(transcription_status IN ('pending', 'processing', 'completed', 'failed')),
            error_message TEXT,
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_recordings_date ON recordings(date DESC);
        CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(transcription_status);

        CREATE TABLE IF NOT EXISTS exercises (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            instruction TEXT NOT NULL,
            content TEXT NOT NULL,
            difficulty INTEGER NOT NULL CHECK(difficulty >= 1 AND difficulty <= 5),
            targetWeakness TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            sourceAnalysisId INTEGER,
            dailySetDate TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_exercises_targetWeakness ON exercises(targetWeakness);
        CREATE INDEX IF NOT EXISTS idx_exercises_dailySetDate ON exercises(dailySetDate);

        CREATE TABLE IF NOT EXISTS exercise_attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exerciseId INTEGER NOT NULL,
            userAnswer TEXT NOT NULL,
            isCorrect INTEGER NOT NULL CHECK(isCorrect IN (0, 1)),
            partialScore REAL,
            feedback TEXT NOT NULL,
            attemptedAt TEXT NOT NULL,
            timeSpentSeconds INTEGER NOT NULL,
            FOREIGN KEY (exerciseId) REFERENCES exercises(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_exercise_attempts_exerciseId ON exercise_attempts(exerciseId);

        CREATE TABLE IF NOT EXISTS weakness_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            weaknessCategory TEXT NOT NULL UNIQUE,
            totalAttempts INTEGER NOT NULL DEFAULT 0,
            correctAttempts INTEGER NOT NULL DEFAULT 0,
            lastPracticed TEXT,
            nextReviewDate TEXT,
            masteryLevel INTEGER NOT NULL DEFAULT 0 CHECK(masteryLevel >= 0 AND masteryLevel <= 100)
        );
        CREATE INDEX IF NOT EXISTS idx_weakness_progress_weaknessCategory ON weakness_progress(weaknessCategory);
        CREATE INDEX IF NOT EXISTS idx_weakness_progress_nextReviewDate ON weakness_progress(nextReviewDate);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTableSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("Error creating table: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    /// Inserts a record and returns its rowid, or nil when the insert was
    /// skipped (60s duplicate window) or failed. Callers use the rowid to
    /// attach focus-evidence sightings; dedup-skipped records must never
    /// reach the matcher (they would double-count wild uses).
    @discardableResult
    func insertRecord(_ record: Record) -> Int64? {
        var insertedRowId: Int64?
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
                    insertedRowId = sqlite3_last_insert_rowid(db)
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
        return insertedRowId
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("DatabaseDidChange"), object: nil)
            }
        }
    }

    /// Trust Center: purge records captured from now-blocked apps
    @discardableResult
    func deleteRecords(forApps appNames: [String]) -> Int {
        let cleanedNames = appNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedNames.isEmpty else { return 0 }

        var deletedCount = 0

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let deleteSQL = "DELETE FROM records WHERE LOWER(active_app) = LOWER(?);"
            var stmt: OpaquePointer?

            for appName in cleanedNames {
                if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, appName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                    if sqlite3_step(stmt) == SQLITE_DONE {
                        deletedCount += Int(sqlite3_changes(db))
                    } else {
                        print("Error deleting records for app \(appName): \(String(cString: sqlite3_errmsg(db)))")
                    }
                }
                sqlite3_finalize(stmt)
                stmt = nil
            }
        }

        if deletedCount > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("DatabaseDidChange"), object: nil)
            }
        }

        return deletedCount
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

    // MARK: - Voice Recordings

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Create a new voice recording entry
    /// - Parameter recording: The VoiceRecording to insert
    /// - Returns: The ID of the newly created recording, or nil if insertion failed
    @discardableResult
    func createRecording(_ recording: VoiceRecording) -> Int64? {
        var insertedId: Int64?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let insertSQL = """
            INSERT INTO recordings (date, start_time, end_time, duration, audio_file_path, transcription, transcription_status, error_message, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                let dateStr = self.iso8601Formatter.string(from: recording.date)
                let startTimeStr = self.iso8601Formatter.string(from: recording.startTime)
                let endTimeStr = self.iso8601Formatter.string(from: recording.endTime)
                let createdAtStr = self.iso8601Formatter.string(from: recording.createdAt)

                sqlite3_bind_text(stmt, 1, dateStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, startTimeStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, endTimeStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(stmt, 4, recording.duration)

                if let audioPath = recording.audioFilePath {
                    sqlite3_bind_text(stmt, 5, audioPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                if let transcription = recording.transcription {
                    sqlite3_bind_text(stmt, 6, transcription, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                sqlite3_bind_text(stmt, 7, recording.transcriptionStatus.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if let errorMsg = recording.errorMessage {
                    sqlite3_bind_text(stmt, 8, errorMsg, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 8)
                }

                sqlite3_bind_text(stmt, 9, createdAtStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                } else {
                    print("[DatabaseService] Error inserting recording: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return insertedId
    }

    /// Update an existing voice recording
    /// - Parameter recording: The VoiceRecording with updated values (must have a valid id)
    /// - Returns: True if update succeeded, false otherwise
    @discardableResult
    func updateRecording(_ recording: VoiceRecording) -> Bool {
        guard let recordingId = recording.id else { return false }

        var success = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let updateSQL = """
            UPDATE recordings
            SET date = ?, start_time = ?, end_time = ?, duration = ?, audio_file_path = ?, transcription = ?, transcription_status = ?, error_message = ?
            WHERE id = ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                let dateStr = self.iso8601Formatter.string(from: recording.date)
                let startTimeStr = self.iso8601Formatter.string(from: recording.startTime)
                let endTimeStr = self.iso8601Formatter.string(from: recording.endTime)

                sqlite3_bind_text(stmt, 1, dateStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, startTimeStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, endTimeStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(stmt, 4, recording.duration)

                if let audioPath = recording.audioFilePath {
                    sqlite3_bind_text(stmt, 5, audioPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                if let transcription = recording.transcription {
                    sqlite3_bind_text(stmt, 6, transcription, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                sqlite3_bind_text(stmt, 7, recording.transcriptionStatus.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if let errorMsg = recording.errorMessage {
                    sqlite3_bind_text(stmt, 8, errorMsg, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 8)
                }

                sqlite3_bind_int64(stmt, 9, recordingId)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    success = sqlite3_changes(db) > 0
                } else {
                    print("[DatabaseService] Error updating recording: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return success
    }

    /// Fetch all recordings for a specific date
    /// - Parameter date: The date to fetch recordings for
    /// - Returns: Array of VoiceRecording objects for that date
    func getRecordingsForDate(_ date: Date) -> [VoiceRecording] {
        var recordings: [VoiceRecording] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let dayStartStr = self.iso8601Formatter.string(from: dayStart)
            let dayEndStr = self.iso8601Formatter.string(from: dayEnd)

            let querySQL = """
            SELECT id, date, start_time, end_time, duration, audio_file_path, transcription, transcription_status, error_message, created_at
            FROM recordings
            WHERE date >= ? AND date < ?
            ORDER BY start_time DESC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, dayStartStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, dayEndStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let recording = self.parseRecordingRow(stmt) {
                        recordings.append(recording)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return recordings
    }

    /// Fetch a single recording by its ID
    /// - Parameter id: The recording ID
    /// - Returns: The VoiceRecording if found, nil otherwise
    func getRecordingById(_ id: Int64) -> VoiceRecording? {
        var recording: VoiceRecording?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, date, start_time, end_time, duration, audio_file_path, transcription, transcription_status, error_message, created_at
            FROM recordings
            WHERE id = ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, id)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    recording = self.parseRecordingRow(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }

        return recording
    }

    /// Delete a recording by its ID
    /// - Parameter id: The recording ID to delete
    /// - Returns: True if deletion succeeded, false otherwise
    @discardableResult
    func deleteRecording(_ id: Int64) -> Bool {
        var success = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let deleteSQL = "DELETE FROM recordings WHERE id = ?;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, id)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    success = sqlite3_changes(db) > 0
                } else {
                    print("[DatabaseService] Error deleting recording: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return success
    }

    /// Fetch all pending recordings that have an audio file path
    /// Used to recover interrupted recordings on app launch
    /// - Returns: Array of VoiceRecording objects with status 'pending' and non-null audioFilePath
    func getPendingRecordingsWithAudioFile() -> [VoiceRecording] {
        var recordings: [VoiceRecording] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, date, start_time, end_time, duration, audio_file_path, transcription, transcription_status, error_message, created_at
            FROM recordings
            WHERE transcription_status = 'pending' AND audio_file_path IS NOT NULL
            ORDER BY start_time DESC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let recording = self.parseRecordingRow(stmt) {
                        recordings.append(recording)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return recordings
    }

    /// Helper method to parse a recording row from SQLite statement
    private func parseRecordingRow(_ stmt: OpaquePointer?) -> VoiceRecording? {
        guard let stmt = stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)

        guard let dateText = sqlite3_column_text(stmt, 1),
              let startTimeText = sqlite3_column_text(stmt, 2),
              let endTimeText = sqlite3_column_text(stmt, 3),
              let statusText = sqlite3_column_text(stmt, 7),
              let createdAtText = sqlite3_column_text(stmt, 9) else {
            return nil
        }

        let dateStr = String(cString: dateText)
        let startTimeStr = String(cString: startTimeText)
        let endTimeStr = String(cString: endTimeText)
        let statusStr = String(cString: statusText)
        let createdAtStr = String(cString: createdAtText)

        guard let date = iso8601Formatter.date(from: dateStr),
              let startTime = iso8601Formatter.date(from: startTimeStr),
              let endTime = iso8601Formatter.date(from: endTimeStr),
              let createdAt = iso8601Formatter.date(from: createdAtStr),
              let status = TranscriptionStatus(rawValue: statusStr) else {
            return nil
        }

        let duration = sqlite3_column_double(stmt, 4)

        var audioFilePath: String?
        if sqlite3_column_type(stmt, 5) != SQLITE_NULL, let audioText = sqlite3_column_text(stmt, 5) {
            audioFilePath = String(cString: audioText)
        }

        var transcription: String?
        if sqlite3_column_type(stmt, 6) != SQLITE_NULL, let transcriptionText = sqlite3_column_text(stmt, 6) {
            transcription = String(cString: transcriptionText)
        }

        var errorMessage: String?
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL, let errorText = sqlite3_column_text(stmt, 8) {
            errorMessage = String(cString: errorText)
        }

        return VoiceRecording(
            id: id,
            date: date,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            audioFilePath: audioFilePath,
            transcription: transcription,
            transcriptionStatus: status,
            errorMessage: errorMessage,
            createdAt: createdAt
        )
    }

    // MARK: - Exercises

    /// Create a new exercise record
    /// - Parameter exercise: The Exercise to insert
    /// - Returns: The ID of the newly created exercise, or nil if insertion failed
    @discardableResult
    func createExercise(_ exercise: Exercise) -> Int64? {
        var insertedId: Int64?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            // Encode content to JSON string
            let encoder = JSONEncoder()
            guard let contentData = try? encoder.encode(exercise.content),
                  let contentJson = String(data: contentData, encoding: .utf8) else {
                print("[DatabaseService] Error encoding exercise content to JSON")
                return
            }

            let createdAtStr = self.iso8601Formatter.string(from: exercise.createdAt)

            let insertSQL = """
            INSERT INTO exercises (type, instruction, content, difficulty, targetWeakness, createdAt, sourceAnalysisId, dailySetDate)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, exercise.type.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, exercise.instruction, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, contentJson, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 4, Int32(exercise.difficulty))
                sqlite3_bind_text(stmt, 5, exercise.targetWeakness, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 6, createdAtStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if let sourceId = exercise.sourceAnalysisId {
                    sqlite3_bind_int64(stmt, 7, sourceId)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }

                if let dailyDate = exercise.dailySetDate {
                    sqlite3_bind_text(stmt, 8, dailyDate, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 8)
                }

                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                } else {
                    print("[DatabaseService] Error inserting exercise: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return insertedId
    }

    /// Get an exercise by its ID
    /// - Parameter id: The exercise ID
    /// - Returns: The Exercise if found, nil otherwise
    func getExerciseById(_ id: Int64) -> Exercise? {
        var exercise: Exercise?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, type, instruction, content, difficulty, targetWeakness, createdAt, sourceAnalysisId, dailySetDate
            FROM exercises
            WHERE id = ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, id)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    exercise = self.parseExerciseRow(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }

        return exercise
    }

    /// Get all exercises for a specific date (dailySetDate)
    /// - Parameter date: The date to fetch exercises for
    /// - Returns: Array of Exercise objects for that date
    func getExercisesForDate(_ date: Date) -> [Exercise] {
        var exercises: [Exercise] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: date)

            let querySQL = """
            SELECT id, type, instruction, content, difficulty, targetWeakness, createdAt, sourceAnalysisId, dailySetDate
            FROM exercises
            WHERE dailySetDate = ?
            ORDER BY createdAt ASC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, dateStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let exercise = self.parseExerciseRow(stmt) {
                        exercises.append(exercise)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return exercises
    }

    /// Check if daily exercises exist for today
    /// - Returns: True if there are exercises with today's date
    func hasDailyExercisesForToday() -> Bool {
        var hasExercises = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayStr = dateFormatter.string(from: Date())

            let querySQL = "SELECT COUNT(*) FROM exercises WHERE dailySetDate = ?;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, todayStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(stmt) == SQLITE_ROW {
                    hasExercises = sqlite3_column_int(stmt, 0) > 0
                }
            }
            sqlite3_finalize(stmt)
        }

        return hasExercises
    }

    /// Get weaknesses from recent AI analysis insights (last N days)
    /// - Parameter days: Number of days to look back (default 7)
    /// - Returns: Array of unique weakness category strings
    func getWeaknessesFromRecentInsights(days: Int = 7) -> [String] {
        var weaknesses: Set<String> = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let cutoffTimestamp = cutoffDate.timeIntervalSince1970

            // Get insights from grammar, phrasing, vocabulary types in the last N days
            let querySQL = """
            SELECT content, insight_type FROM insights
            WHERE date_range_start >= ?
            AND insight_type IN ('grammar', 'phrasing', 'vocabulary')
            ORDER BY created_at DESC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoffTimestamp)

                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let contentText = sqlite3_column_text(stmt, 0),
                          let typeText = sqlite3_column_text(stmt, 1) else { continue }

                    let contentStr = String(cString: contentText)
                    let typeStr = String(cString: typeText)

                    // Extract weaknesses based on insight type
                    self.extractWeaknessesFromContent(contentStr, type: typeStr, into: &weaknesses)
                }
            }
            sqlite3_finalize(stmt)
        }

        // Also include existing weakness categories from weakness_progress
        let existingProgress = getAllWeaknessProgress()
        for progress in existingProgress {
            weaknesses.insert(progress.weaknessCategory)
        }

        return Array(weaknesses)
    }

    /// Extract weakness categories from insight content JSON
    private func extractWeaknessesFromContent(_ content: String, type: String, into weaknesses: inout Set<String>) {
        guard let data = content.data(using: .utf8) else { return }

        // Try to parse as AnalysisResult first
        if let analysisResult = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
            // Extract categories from grammar issues
            for issue in analysisResult.grammarIssues {
                weaknesses.insert("Grammar: \(categorizeGrammarIssue(issue.explanation))")
            }
            // Extract from phrasing issues
            for issue in analysisResult.phrasingIssues {
                weaknesses.insert("Phrasing: Natural expressions")
            }
            // Extract from vocabulary
            for insight in analysisResult.vocabularyInsights {
                weaknesses.insert("Vocabulary: Word choice")
            }
            return
        }

        // Parse based on insight type
        switch type {
        case "grammar":
            if let issues = try? JSONDecoder().decode([GrammarIssue].self, from: data) {
                for issue in issues {
                    weaknesses.insert("Grammar: \(categorizeGrammarIssue(issue.explanation))")
                }
            }
        case "phrasing":
            if let issues = try? JSONDecoder().decode([PhrasingIssue].self, from: data) {
                if !issues.isEmpty {
                    weaknesses.insert("Phrasing: Natural expressions")
                }
            }
        case "vocabulary":
            if let insights = try? JSONDecoder().decode([VocabularyInsight].self, from: data) {
                if !insights.isEmpty {
                    weaknesses.insert("Vocabulary: Word choice")
                }
            }
        default:
            break
        }
    }

    /// Categorize a grammar issue into a broader category
    private func categorizeGrammarIssue(_ explanation: String) -> String {
        let lowercased = explanation.lowercased()

        if lowercased.contains("article") || lowercased.contains("a/an") || lowercased.contains("the") {
            return "Articles"
        } else if lowercased.contains("tense") || lowercased.contains("past") || lowercased.contains("present") || lowercased.contains("future") {
            return "Verb tenses"
        } else if lowercased.contains("preposition") {
            return "Prepositions"
        } else if lowercased.contains("subject-verb") || lowercased.contains("agreement") {
            return "Subject-verb agreement"
        } else if lowercased.contains("plural") || lowercased.contains("singular") {
            return "Plurals"
        } else if lowercased.contains("pronoun") {
            return "Pronouns"
        } else if lowercased.contains("word order") {
            return "Word order"
        } else if lowercased.contains("comma") || lowercased.contains("punctuation") {
            return "Punctuation"
        } else {
            return "General"
        }
    }

    /// Helper method to parse an exercise row from SQLite statement
    private func parseExerciseRow(_ stmt: OpaquePointer?) -> Exercise? {
        guard let stmt = stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)

        guard let typeText = sqlite3_column_text(stmt, 1),
              let instructionText = sqlite3_column_text(stmt, 2),
              let contentText = sqlite3_column_text(stmt, 3),
              let targetWeaknessText = sqlite3_column_text(stmt, 5),
              let createdAtText = sqlite3_column_text(stmt, 6) else {
            return nil
        }

        let typeStr = String(cString: typeText)
        let instruction = String(cString: instructionText)
        let contentStr = String(cString: contentText)
        let targetWeakness = String(cString: targetWeaknessText)
        let createdAtStr = String(cString: createdAtText)

        guard let exerciseType = ExerciseType(rawValue: typeStr),
              let createdAt = iso8601Formatter.date(from: createdAtStr) else {
            return nil
        }

        let difficulty = Int(sqlite3_column_int(stmt, 4))

        // Decode content JSON
        guard let contentData = contentStr.data(using: .utf8),
              let content = try? JSONDecoder().decode(ExerciseContent.self, from: contentData) else {
            return nil
        }

        var sourceAnalysisId: Int64?
        if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
            sourceAnalysisId = sqlite3_column_int64(stmt, 7)
        }

        var dailySetDate: String?
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL, let dailyText = sqlite3_column_text(stmt, 8) {
            dailySetDate = String(cString: dailyText)
        }

        return Exercise(
            id: id,
            type: exerciseType,
            instruction: instruction,
            content: content,
            difficulty: difficulty,
            targetWeakness: targetWeakness,
            createdAt: createdAt,
            sourceAnalysisId: sourceAnalysisId,
            dailySetDate: dailySetDate
        )
    }

    /// Check if an exercise has been successfully completed (has a correct attempt)
    /// - Parameter exerciseId: The exercise ID
    /// - Returns: True if there's at least one correct attempt for this exercise
    func isExerciseCompleted(_ exerciseId: Int64) -> Bool {
        var isCompleted = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT COUNT(*) FROM exercise_attempts WHERE exerciseId = ? AND isCorrect = 1;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, exerciseId)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    isCompleted = sqlite3_column_int(stmt, 0) > 0
                }
            }
            sqlite3_finalize(stmt)
        }

        return isCompleted
    }

    /// Get count of completed exercises for a specific date
    /// - Parameter date: The date to check
    /// - Returns: Number of exercises with correct attempts for that date
    func getCompletedExerciseCount(for date: Date) -> Int {
        var count = 0

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: date)

            let querySQL = """
            SELECT COUNT(DISTINCT e.id)
            FROM exercises e
            INNER JOIN exercise_attempts ea ON e.id = ea.exerciseId
            WHERE e.dailySetDate = ? AND ea.isCorrect = 1;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, dateStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }

        return count
    }

    // MARK: - Exercise Attempts

    /// Create a new exercise attempt record
    /// - Parameters:
    ///   - exerciseId: The ID of the exercise attempted
    ///   - userAnswer: The user's answer as a JSON-encodable object
    ///   - isCorrect: Whether the answer was fully correct
    ///   - partialScore: Optional partial score (0.0-1.0) for multi-part exercises
    ///   - feedback: Feedback string to show the user
    ///   - timeSpentSeconds: Time spent on the exercise in seconds
    /// - Returns: The ID of the newly created attempt, or nil if insertion failed
    @discardableResult
    func createAttempt(exerciseId: Int64, userAnswer: Codable, isCorrect: Bool, partialScore: Double?, feedback: String, timeSpentSeconds: Int) -> Int64? {
        var insertedId: Int64?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            // Encode userAnswer to JSON string
            let encoder = JSONEncoder()
            guard let answerData = try? encoder.encode(AnyEncodable(userAnswer)),
                  let answerJson = String(data: answerData, encoding: .utf8) else {
                print("[DatabaseService] Error encoding userAnswer to JSON")
                return
            }

            let attemptedAt = self.iso8601Formatter.string(from: Date())

            let insertSQL = """
            INSERT INTO exercise_attempts (exerciseId, userAnswer, isCorrect, partialScore, feedback, attemptedAt, timeSpentSeconds)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, exerciseId)
                sqlite3_bind_text(stmt, 2, answerJson, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 3, isCorrect ? 1 : 0)

                if let score = partialScore {
                    sqlite3_bind_double(stmt, 4, score)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }

                sqlite3_bind_text(stmt, 5, feedback, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 6, attemptedAt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 7, Int32(timeSpentSeconds))

                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                } else {
                    print("[DatabaseService] Error inserting exercise attempt: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return insertedId
    }

    /// Get the target weakness for an exercise by ID
    /// - Parameter exerciseId: The exercise ID
    /// - Returns: The target weakness category string, or nil if not found
    func getExerciseTargetWeakness(exerciseId: Int64) -> String? {
        var weakness: String?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT targetWeakness FROM exercises WHERE id = ?;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, exerciseId)

                if sqlite3_step(stmt) == SQLITE_ROW, let weaknessText = sqlite3_column_text(stmt, 0) {
                    weakness = String(cString: weaknessText)
                }
            }
            sqlite3_finalize(stmt)
        }

        return weakness
    }

    // MARK: - Weakness Progress

    /// Get or create a weakness progress record for a given category
    /// - Parameter category: The weakness category name
    /// - Returns: The existing or newly created WeaknessProgress
    func getOrCreateWeaknessProgress(category: String) -> WeaknessProgress {
        var progress: WeaknessProgress?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            // First try to get existing
            let selectSQL = "SELECT id, weaknessCategory, totalAttempts, correctAttempts, lastPracticed, nextReviewDate, masteryLevel FROM weakness_progress WHERE weaknessCategory = ?;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, category, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(stmt) == SQLITE_ROW {
                    progress = self.parseWeaknessProgressRow(stmt)
                }
            }
            sqlite3_finalize(stmt)

            // If not found, create new
            if progress == nil {
                let insertSQL = "INSERT INTO weakness_progress (weaknessCategory, totalAttempts, correctAttempts, masteryLevel) VALUES (?, 0, 0, 0);"

                if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, category, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                    if sqlite3_step(stmt) == SQLITE_DONE {
                        let id = sqlite3_last_insert_rowid(db)
                        progress = WeaknessProgress(id: id, weaknessCategory: category)
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        return progress ?? WeaknessProgress(weaknessCategory: category)
    }

    /// Update an existing weakness progress record
    /// - Parameter progress: The updated WeaknessProgress
    /// - Returns: True if update succeeded, false otherwise
    @discardableResult
    func updateWeaknessProgress(_ progress: WeaknessProgress) -> Bool {
        guard let progressId = progress.id else { return false }

        var success = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let updateSQL = """
            UPDATE weakness_progress
            SET totalAttempts = ?, correctAttempts = ?, lastPracticed = ?, nextReviewDate = ?, masteryLevel = ?
            WHERE id = ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(progress.totalAttempts))
                sqlite3_bind_int(stmt, 2, Int32(progress.correctAttempts))

                if let lastPracticed = progress.lastPracticed {
                    let dateStr = self.iso8601Formatter.string(from: lastPracticed)
                    sqlite3_bind_text(stmt, 3, dateStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 3)
                }

                if let nextReviewDate = progress.nextReviewDate {
                    let dateStr = self.iso8601Formatter.string(from: nextReviewDate)
                    sqlite3_bind_text(stmt, 4, dateStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 4)
                }

                sqlite3_bind_int(stmt, 5, Int32(progress.masteryLevel))
                sqlite3_bind_int64(stmt, 6, progressId)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    success = sqlite3_changes(db) > 0
                } else {
                    print("[DatabaseService] Error updating weakness progress: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return success
    }

    /// Get all weakness progress records
    /// - Returns: Array of all WeaknessProgress records
    func getAllWeaknessProgress() -> [WeaknessProgress] {
        var progressList: [WeaknessProgress] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT id, weaknessCategory, totalAttempts, correctAttempts, lastPracticed, nextReviewDate, masteryLevel FROM weakness_progress ORDER BY masteryLevel ASC;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let progress = self.parseWeaknessProgressRow(stmt) {
                        progressList.append(progress)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return progressList
    }

    /// Get weakness progress records that are due for review (nextReviewDate <= today)
    /// - Returns: Array of WeaknessProgress records due for review
    func getWeaknessesDueForReview() -> [WeaknessProgress] {
        var progressList: [WeaknessProgress] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let today = self.iso8601Formatter.string(from: Calendar.current.startOfDay(for: Date()))

            let querySQL = """
            SELECT id, weaknessCategory, totalAttempts, correctAttempts, lastPracticed, nextReviewDate, masteryLevel
            FROM weakness_progress
            WHERE nextReviewDate IS NOT NULL AND nextReviewDate <= ?
            ORDER BY nextReviewDate ASC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, today, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let progress = self.parseWeaknessProgressRow(stmt) {
                        progressList.append(progress)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return progressList
    }

    /// Get the last N attempts for a specific weakness category
    /// - Parameters:
    ///   - category: The weakness category
    ///   - limit: Maximum number of attempts to retrieve (default 10)
    /// - Returns: Array of tuples containing (isCorrect, attemptedAt)
    func getRecentAttemptsForWeakness(category: String, limit: Int = 10) -> [(isCorrect: Bool, attemptedAt: Date)] {
        var attempts: [(isCorrect: Bool, attemptedAt: Date)] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT ea.isCorrect, ea.attemptedAt
            FROM exercise_attempts ea
            INNER JOIN exercises e ON ea.exerciseId = e.id
            WHERE e.targetWeakness = ?
            ORDER BY ea.attemptedAt DESC
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, category, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 2, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let isCorrect = sqlite3_column_int(stmt, 0) == 1
                    if let attemptedAtText = sqlite3_column_text(stmt, 1) {
                        let attemptedAtStr = String(cString: attemptedAtText)
                        if let attemptedAt = self.iso8601Formatter.date(from: attemptedAtStr) {
                            attempts.append((isCorrect: isCorrect, attemptedAt: attemptedAt))
                        }
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return attempts
    }

    /// Update weakness progress after an exercise attempt using spaced repetition
    /// - Parameters:
    ///   - exerciseId: The ID of the exercise that was attempted
    ///   - isCorrect: Whether the answer was correct
    /// - Returns: True if update succeeded, false otherwise
    @discardableResult
    func updateWeaknessAfterAttempt(exerciseId: Int64, isCorrect: Bool) -> Bool {
        // Get the target weakness for this exercise
        guard let targetWeakness = getExerciseTargetWeakness(exerciseId: exerciseId) else {
            print("[DatabaseService] Cannot update weakness: exercise \(exerciseId) has no target weakness")
            return false
        }

        // Get or create the weakness progress record
        var progress = getOrCreateWeaknessProgress(category: targetWeakness)

        // Update attempt counts
        progress.totalAttempts += 1
        if isCorrect {
            progress.correctAttempts += 1
        }

        // Update lastPracticed to now
        progress.lastPracticed = Date()

        // Calculate mastery level based on last 10 attempts (recent weighted higher)
        let recentAttempts = getRecentAttemptsForWeakness(category: targetWeakness, limit: 10)
        progress.masteryLevel = calculateMasteryLevel(from: recentAttempts)

        // Calculate next review date using spaced repetition intervals
        progress.nextReviewDate = calculateNextReviewDate(isCorrect: isCorrect, currentProgress: progress)

        // Save the updated progress
        return updateWeaknessProgress(progress)
    }

    /// Calculate mastery level as a weighted average of recent attempts (0-100)
    /// More recent attempts are weighted higher
    /// - Parameter attempts: Array of recent attempts (most recent first)
    /// - Returns: Mastery level from 0 to 100
    private func calculateMasteryLevel(from attempts: [(isCorrect: Bool, attemptedAt: Date)]) -> Int {
        guard !attempts.isEmpty else { return 0 }

        // Use exponential weighting: most recent = weight 10, next = 9, etc.
        var totalWeight: Double = 0
        var weightedCorrect: Double = 0

        for (index, attempt) in attempts.enumerated() {
            let weight = Double(attempts.count - index)  // Higher weight for more recent
            totalWeight += weight
            if attempt.isCorrect {
                weightedCorrect += weight
            }
        }

        let masteryPercentage = (weightedCorrect / totalWeight) * 100
        return Int(masteryPercentage.rounded())
    }

    /// Calculate next review date using spaced repetition
    /// Intervals: correct increases (1→3→7→14→30 days), incorrect resets to 1 day
    /// - Parameters:
    ///   - isCorrect: Whether the current attempt was correct
    ///   - currentProgress: The current weakness progress
    /// - Returns: The next review date
    private func calculateNextReviewDate(isCorrect: Bool, currentProgress: WeaknessProgress) -> Date {
        let calendar = Calendar.current
        let reviewIntervals = [1, 3, 7, 14, 30]  // Days

        // Determine current interval based on mastery and last review pattern
        // Higher mastery = longer interval, incorrect resets to shortest
        let intervalIndex: Int
        if isCorrect {
            // Progress based on mastery level
            if currentProgress.masteryLevel >= 80 {
                intervalIndex = 4  // 30 days
            } else if currentProgress.masteryLevel >= 60 {
                intervalIndex = 3  // 14 days
            } else if currentProgress.masteryLevel >= 40 {
                intervalIndex = 2  // 7 days
            } else if currentProgress.masteryLevel >= 20 {
                intervalIndex = 1  // 3 days
            } else {
                intervalIndex = 0  // 1 day
            }
        } else {
            // Incorrect answer resets to shortest interval
            intervalIndex = 0  // 1 day
        }

        let daysUntilReview = reviewIntervals[intervalIndex]
        return calendar.date(byAdding: .day, value: daysUntilReview, to: Date()) ?? Date()
    }

    /// Helper method to parse a weakness progress row from SQLite statement
    private func parseWeaknessProgressRow(_ stmt: OpaquePointer?) -> WeaknessProgress? {
        guard let stmt = stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)

        guard let categoryText = sqlite3_column_text(stmt, 1) else { return nil }
        let category = String(cString: categoryText)

        let totalAttempts = Int(sqlite3_column_int(stmt, 2))
        let correctAttempts = Int(sqlite3_column_int(stmt, 3))

        var lastPracticed: Date?
        if sqlite3_column_type(stmt, 4) != SQLITE_NULL, let lastPracticedText = sqlite3_column_text(stmt, 4) {
            lastPracticed = iso8601Formatter.date(from: String(cString: lastPracticedText))
        }

        var nextReviewDate: Date?
        if sqlite3_column_type(stmt, 5) != SQLITE_NULL, let nextReviewText = sqlite3_column_text(stmt, 5) {
            nextReviewDate = iso8601Formatter.date(from: String(cString: nextReviewText))
        }

        let masteryLevel = Int(sqlite3_column_int(stmt, 6))

        return WeaknessProgress(
            id: id,
            weaknessCategory: category,
            totalAttempts: totalAttempts,
            correctAttempts: correctAttempts,
            lastPracticed: lastPracticed,
            nextReviewDate: nextReviewDate,
            masteryLevel: masteryLevel
        )
    }

    // MARK: - Exercise Statistics

    /// Statistics structure for practice progress tracking
    struct ExerciseStatistics {
        var totalAttempts: Int = 0
        var correctAttempts: Int = 0
        var accuracyPercentage: Double = 0
        var currentStreak: Int = 0
    }

    /// Get overall exercise statistics for progress tracking
    /// - Returns: ExerciseStatistics containing total attempts, accuracy, and streak
    func getExerciseStatistics() -> ExerciseStatistics {
        var stats = ExerciseStatistics()

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            // Get total and correct attempts
            let statsSQL = """
            SELECT COUNT(*) as total, SUM(isCorrect) as correct
            FROM exercise_attempts;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, statsSQL, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    stats.totalAttempts = Int(sqlite3_column_int(stmt, 0))
                    stats.correctAttempts = Int(sqlite3_column_int(stmt, 1))
                }
            }
            sqlite3_finalize(stmt)

            // Calculate accuracy
            if stats.totalAttempts > 0 {
                stats.accuracyPercentage = Double(stats.correctAttempts) / Double(stats.totalAttempts) * 100
            }

            // Calculate current streak (consecutive days with at least one attempt)
            stats.currentStreak = self.calculateCurrentStreak(db: db)
        }

        return stats
    }

    /// Calculate the current streak of consecutive practice days
    /// - Parameter db: The database pointer
    /// - Returns: Number of consecutive days with practice (including today)
    private func calculateCurrentStreak(db: OpaquePointer) -> Int {
        var streak = 0
        let calendar = Calendar.current

        // Get all unique dates with attempts, ordered descending
        let streakSQL = """
        SELECT DISTINCT date(attemptedAt) as practice_date
        FROM exercise_attempts
        ORDER BY practice_date DESC;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, streakSQL, -1, &stmt, nil) == SQLITE_OK {
            var expectedDate = calendar.startOfDay(for: Date())
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let dateText = sqlite3_column_text(stmt, 0) else { break }
                let dateStr = String(cString: dateText)

                guard let practiceDate = dateFormatter.date(from: dateStr) else { break }
                let practiceDateStart = calendar.startOfDay(for: practiceDate)

                // Check if this date matches the expected date in the streak
                if practiceDateStart == expectedDate {
                    streak += 1
                    // Move expected date to previous day
                    expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
                } else if practiceDateStart < expectedDate {
                    // If the practice date is older than expected, streak is broken
                    // But first check if we're on the first iteration (today might not have practice)
                    if streak == 0 {
                        // Allow streak to start from yesterday if no practice today
                        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
                        if practiceDateStart == yesterday {
                            streak = 1
                            expectedDate = calendar.date(byAdding: .day, value: -1, to: yesterday) ?? yesterday
                            continue
                        }
                    }
                    break
                }
            }
        }
        sqlite3_finalize(stmt)

        return streak
    }

}

// MARK: - Focus Engine (focus_items, focus_evidence, language_profile, morning_briefs)

extension DatabaseService {

    /// Additive-only migration. Before the focus tables exist for the first time,
    /// WAL-checkpoint and copy the database to a timestamped backup (a bare file
    /// copy is NOT safe under WAL mode). Existing tables are never touched.
    private func createFocusTablesWithBackup() {
        var focusTablesExist = false
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='focus_items';", -1, &stmt, nil) == SQLITE_OK {
                focusTablesExist = sqlite3_step(stmt) == SQLITE_ROW
            }
            sqlite3_finalize(stmt)

            if !focusTablesExist {
                self.backupDatabaseFile(db: db)
            }

            let createSQL = """
            CREATE TABLE IF NOT EXISTS focus_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL CHECK(kind IN ('enrich','fix')),
                status TEXT NOT NULL CHECK(status IN ('candidate','queued','practicing','spotted','adopted','retired')),
                target_phrase TEXT NOT NULL,
                match_forms TEXT NOT NULL,
                rationale TEXT NOT NULL,
                priority INTEGER NOT NULL DEFAULT 0,
                supersedes_item_id INTEGER,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_focus_items_status ON focus_items(status);

            CREATE TABLE IF NOT EXISTS focus_evidence (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                focus_item_id INTEGER NOT NULL REFERENCES focus_items(id),
                record_id INTEGER,
                excerpt TEXT NOT NULL,
                app TEXT,
                evidence_type TEXT NOT NULL CHECK(evidence_type IN ('overuse','mistake','correct_use','near_miss','practice')),
                verified INTEGER NOT NULL DEFAULT 0,
                occurred_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_focus_evidence_item ON focus_evidence(focus_item_id);

            CREATE TABLE IF NOT EXISTS language_profile (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                version INTEGER NOT NULL,
                content TEXT NOT NULL,
                based_on_date REAL NOT NULL,
                created_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS morning_briefs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                for_date REAL NOT NULL,
                focus_item_id INTEGER NOT NULL REFERENCES focus_items(id),
                headline TEXT NOT NULL,
                mission TEXT NOT NULL,
                wins TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_morning_briefs_date ON morning_briefs(for_date);
            """

            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
                if let errMsg = errMsg {
                    print("[DatabaseService] Error creating focus tables: \(String(cString: errMsg))")
                    sqlite3_free(errMsg)
                }
            }
        }
    }

    /// Checkpoint-then-copy backup. Must run on dbQueue with a valid db handle.
    private func backupDatabaseFile(db: OpaquePointer) {
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)

        let fileManager = FileManager.default
        let dbPath = getDatabasePath()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupPath = dbPath.replacingOccurrences(of: "records.sqlite", with: "records-backup-\(stamp).sqlite")

        do {
            try fileManager.copyItem(atPath: dbPath, toPath: backupPath)
            for suffix in ["-wal", "-shm"] {
                let sidecar = dbPath + suffix
                if fileManager.fileExists(atPath: sidecar) {
                    try? fileManager.copyItem(atPath: sidecar, toPath: backupPath + suffix)
                }
            }
            print("[DatabaseService] Pre-migration backup created: \(backupPath)")
        } catch {
            print("[DatabaseService] WARNING: pre-migration backup failed: \(error)")
        }
    }

    // MARK: Focus Items

    @discardableResult
    func insertFocusItem(_ item: FocusItem) -> Int64? {
        var insertedId: Int64?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            guard let formsData = try? JSONEncoder().encode(item.matchForms),
                  let formsJson = String(data: formsData, encoding: .utf8) else { return }

            let insertSQL = """
            INSERT INTO focus_items (kind, status, target_phrase, match_forms, rationale, priority, supersedes_item_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, item.kind.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, item.status.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, item.targetPhrase, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, formsJson, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 5, item.rationale, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 6, Int32(item.priority))
                if let supersedes = item.supersedesItemId {
                    sqlite3_bind_int64(stmt, 7, supersedes)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                sqlite3_bind_double(stmt, 8, item.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 9, item.updatedAt.timeIntervalSince1970)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                } else {
                    print("[DatabaseService] Error inserting focus item: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return insertedId
    }

    func getFocusItems(statuses: [FocusItemStatus]) -> [FocusItem] {
        var items: [FocusItem] = []
        guard !statuses.isEmpty else { return items }

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let placeholders = statuses.map { _ in "?" }.joined(separator: ",")
            let querySQL = """
            SELECT id, kind, status, target_phrase, match_forms, rationale, priority, supersedes_item_id, created_at, updated_at
            FROM focus_items
            WHERE status IN (\(placeholders))
            ORDER BY priority ASC, created_at ASC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                for (index, status) in statuses.enumerated() {
                    sqlite3_bind_text(stmt, Int32(index + 1), status.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let item = self.parseFocusItemRow(stmt) {
                        items.append(item)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return items
    }

    func getFocusItem(byId id: Int64) -> FocusItem? {
        var item: FocusItem?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, kind, status, target_phrase, match_forms, rationale, priority, supersedes_item_id, created_at, updated_at
            FROM focus_items WHERE id = ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, id)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    item = self.parseFocusItemRow(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }

        return item
    }

    /// Phrase lookup is case-insensitive: the AI references items by normalized targetPhrase.
    func getFocusItem(byPhrase phrase: String) -> FocusItem? {
        var item: FocusItem?
        let normalized = FocusItem.normalize(phrase)

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, kind, status, target_phrase, match_forms, rationale, priority, supersedes_item_id, created_at, updated_at
            FROM focus_items
            WHERE LOWER(TRIM(target_phrase)) = ?
            ORDER BY created_at DESC LIMIT 1;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, normalized, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    item = self.parseFocusItemRow(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }

        return item
    }

    @discardableResult
    func updateFocusItemStatus(id: Int64, status: FocusItemStatus) -> Bool {
        var success = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let updateSQL = "UPDATE focus_items SET status = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, status.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 3, id)
                success = sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
            }
            sqlite3_finalize(stmt)
        }

        if success {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("FocusQueueDidChange"), object: nil)
            }
        }
        return success
    }

    @discardableResult
    func updateFocusItemPriority(id: Int64, priority: Int) -> Bool {
        var success = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let updateSQL = "UPDATE focus_items SET priority = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(priority))
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 3, id)
                success = sqlite3_step(stmt) == SQLITE_DONE
            }
            sqlite3_finalize(stmt)
        }

        return success
    }

    private func parseFocusItemRow(_ stmt: OpaquePointer?) -> FocusItem? {
        guard let stmt = stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)
        guard let kindText = sqlite3_column_text(stmt, 1),
              let statusText = sqlite3_column_text(stmt, 2),
              let phraseText = sqlite3_column_text(stmt, 3),
              let formsText = sqlite3_column_text(stmt, 4),
              let rationaleText = sqlite3_column_text(stmt, 5) else { return nil }

        guard let kind = FocusItemKind(rawValue: String(cString: kindText)),
              let status = FocusItemStatus(rawValue: String(cString: statusText)) else { return nil }

        let formsJson = String(cString: formsText)
        let matchForms = (try? JSONDecoder().decode([String].self, from: Data(formsJson.utf8))) ?? []

        var supersedes: Int64?
        if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
            supersedes = sqlite3_column_int64(stmt, 7)
        }

        return FocusItem(
            id: id,
            kind: kind,
            status: status,
            targetPhrase: String(cString: phraseText),
            matchForms: matchForms,
            rationale: String(cString: rationaleText),
            priority: Int(sqlite3_column_int(stmt, 6)),
            supersedesItemId: supersedes,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
        )
    }

    // MARK: Focus Evidence

    @discardableResult
    func insertFocusEvidence(_ evidence: FocusEvidence) -> Int64? {
        var insertedId: Int64?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let insertSQL = """
            INSERT INTO focus_evidence (focus_item_id, record_id, excerpt, app, evidence_type, verified, occurred_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, evidence.focusItemId)
                if let recordId = evidence.recordId {
                    sqlite3_bind_int64(stmt, 2, recordId)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_text(stmt, 3, evidence.excerpt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if let app = evidence.app {
                    sqlite3_bind_text(stmt, 4, app, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                sqlite3_bind_text(stmt, 5, evidence.evidenceType.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 6, evidence.verified ? 1 : 0)
                sqlite3_bind_double(stmt, 7, evidence.occurredAt.timeIntervalSince1970)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                } else {
                    print("[DatabaseService] Error inserting focus evidence: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }

        return insertedId
    }

    func getFocusEvidence(forItem itemId: Int64) -> [FocusEvidence] {
        var evidence: [FocusEvidence] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, focus_item_id, record_id, excerpt, app, evidence_type, verified, occurred_at
            FROM focus_evidence WHERE focus_item_id = ? ORDER BY occurred_at ASC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, itemId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let row = self.parseFocusEvidenceRow(stmt) {
                        evidence.append(row)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return evidence
    }

    /// Pending sightings awaiting AI review (verified = 0)
    func getPendingFocusEvidence() -> [FocusEvidence] {
        var evidence: [FocusEvidence] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, focus_item_id, record_id, excerpt, app, evidence_type, verified, occurred_at
            FROM focus_evidence WHERE verified = 0 ORDER BY occurred_at ASC;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let row = self.parseFocusEvidenceRow(stmt) {
                        evidence.append(row)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return evidence
    }

    /// Applies an AI verdict to a pending sighting. Idempotent: re-applying a
    /// verdict to an already-verified row is a no-op (returns false).
    @discardableResult
    func applyEvidenceVerdict(evidenceId: Int64, correct: Bool) -> Bool {
        var applied = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let newType = correct ? FocusEvidenceType.correctUse.rawValue : FocusEvidenceType.nearMiss.rawValue
            let updateSQL = "UPDATE focus_evidence SET verified = 1, evidence_type = ? WHERE id = ? AND verified = 0;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, newType, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int64(stmt, 2, evidenceId)
                applied = sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
            }
            sqlite3_finalize(stmt)
        }

        return applied
    }

    /// Wild-use count is always computed, never stored (no dual-write drift)
    func countVerifiedCorrectUses(forItem itemId: Int64) -> Int {
        var count = 0

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT COUNT(*) FROM focus_evidence WHERE focus_item_id = ? AND verified = 1 AND evidence_type = 'correct_use';"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, itemId)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }

        return count
    }

    /// Dedup for AI-cited evidence: same item + same excerpt already recorded
    func focusEvidenceExists(itemId: Int64, excerpt: String) -> Bool {
        var exists = false

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT COUNT(*) FROM focus_evidence WHERE focus_item_id = ? AND excerpt = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, itemId)
                sqlite3_bind_text(stmt, 2, excerpt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    exists = sqlite3_column_int(stmt, 0) > 0
                }
            }
            sqlite3_finalize(stmt)
        }

        return exists
    }

    private func parseFocusEvidenceRow(_ stmt: OpaquePointer?) -> FocusEvidence? {
        guard let stmt = stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)
        let itemId = sqlite3_column_int64(stmt, 1)

        var recordId: Int64?
        if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
            recordId = sqlite3_column_int64(stmt, 2)
        }

        guard let excerptText = sqlite3_column_text(stmt, 3),
              let typeText = sqlite3_column_text(stmt, 5),
              let type = FocusEvidenceType(rawValue: String(cString: typeText)) else { return nil }

        var app: String?
        if sqlite3_column_type(stmt, 4) != SQLITE_NULL, let appText = sqlite3_column_text(stmt, 4) {
            app = String(cString: appText)
        }

        return FocusEvidence(
            id: id,
            focusItemId: itemId,
            recordId: recordId,
            excerpt: String(cString: excerptText),
            app: app,
            evidenceType: type,
            verified: sqlite3_column_int(stmt, 6) == 1,
            occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        )
    }

    // MARK: Language Profile

    func getLatestProfileVersion() -> LanguageProfileVersion? {
        var profile: LanguageProfileVersion?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = "SELECT id, version, content, based_on_date, created_at FROM language_profile ORDER BY version DESC LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW, let contentText = sqlite3_column_text(stmt, 2) {
                    profile = LanguageProfileVersion(
                        id: sqlite3_column_int64(stmt, 0),
                        version: Int(sqlite3_column_int(stmt, 1)),
                        content: String(cString: contentText),
                        basedOnDate: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                    )
                }
            }
            sqlite3_finalize(stmt)
        }

        return profile
    }

    @discardableResult
    func insertProfileVersion(content: String, basedOnDate: Date) -> Int64? {
        let nextVersion = (getLatestProfileVersion()?.version ?? 0) + 1
        var insertedId: Int64?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let insertSQL = "INSERT INTO language_profile (version, content, based_on_date, created_at) VALUES (?, ?, ?, ?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(nextVersion))
                sqlite3_bind_text(stmt, 2, content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(stmt, 3, basedOnDate.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                }
            }
            sqlite3_finalize(stmt)
        }

        return insertedId
    }

    // MARK: Morning Briefs

    /// Unique-replace per day: re-running an analysis rewrites that day's brief
    @discardableResult
    func upsertMorningBrief(forDate: Date, focusItemId: Int64, headline: String, mission: String, wins: [String]) -> Bool {
        var success = false
        let dayStart = Calendar.current.startOfDay(for: forDate)

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            guard let winsData = try? JSONEncoder().encode(wins),
                  let winsJson = String(data: winsData, encoding: .utf8) else { return }

            let upsertSQL = """
            INSERT INTO morning_briefs (for_date, focus_item_id, headline, mission, wins, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(for_date) DO UPDATE SET
                focus_item_id = excluded.focus_item_id,
                headline = excluded.headline,
                mission = excluded.mission,
                wins = excluded.wins,
                created_at = excluded.created_at;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, dayStart.timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 2, focusItemId)
                sqlite3_bind_text(stmt, 3, headline, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, mission, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 5, winsJson, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
                success = sqlite3_step(stmt) == SQLITE_DONE
            }
            sqlite3_finalize(stmt)
        }

        if success {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("FocusQueueDidChange"), object: nil)
            }
        }
        return success
    }

    func getMorningBrief(forDate date: Date) -> MorningBrief? {
        let dayStart = Calendar.current.startOfDay(for: date)
        return fetchBrief(whereSQL: "WHERE for_date = ?", bind: { stmt in
            sqlite3_bind_double(stmt, 1, dayStart.timeIntervalSince1970)
        })
    }

    /// Fallback for stale-brief rendering ("Wednesday's brief")
    func getLatestMorningBrief() -> MorningBrief? {
        return fetchBrief(whereSQL: "", bind: { _ in })
    }

    private func fetchBrief(whereSQL: String, bind: (OpaquePointer?) -> Void) -> MorningBrief? {
        var brief: MorningBrief?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let querySQL = """
            SELECT id, for_date, focus_item_id, headline, mission, wins, created_at
            FROM morning_briefs \(whereSQL) ORDER BY for_date DESC LIMIT 1;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
                bind(stmt)
                if sqlite3_step(stmt) == SQLITE_ROW,
                   let headlineText = sqlite3_column_text(stmt, 3),
                   let missionText = sqlite3_column_text(stmt, 4),
                   let winsText = sqlite3_column_text(stmt, 5) {
                    let winsJson = String(cString: winsText)
                    let wins = (try? JSONDecoder().decode([String].self, from: Data(winsJson.utf8))) ?? []
                    brief = MorningBrief(
                        id: sqlite3_column_int64(stmt, 0),
                        forDate: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                        focusItemId: sqlite3_column_int64(stmt, 2),
                        headline: String(cString: headlineText),
                        mission: String(cString: missionText),
                        wins: wins,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                    )
                }
            }
            sqlite3_finalize(stmt)
        }

        return brief
    }
}

// MARK: - AnyEncodable Helper

/// A type-erased wrapper for encoding any Codable value
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
