import Foundation
import SQLite3

/// Tells SQLite to copy bound text: the bridged NSString buffers don't outlive the bind call
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A persistent tracker for application performance metrics using SQLite.
class LatencyTracker {
    static let shared = LatencyTracker()
    
    private var db: OpaquePointer?
    private let dbPath: String
    // All SQLite access goes through this queue: keeps disk I/O off the main thread
    // and never uses the connection from two threads at once
    private let queue = DispatchQueue(label: "com.wispr.latency-tracker", qos: .utility)
    
    /// Columns every insert writes. Databases created by earlier versions of this file can lack some
    /// of them (e.g. they have `total_turnaround` instead of `total_latency`); missing ones are added.
    private static let expectedColumns: [(name: String, type: String)] = [
        ("session_id", "TEXT"), ("clip_duration", "REAL"), ("decode_time", "REAL"),
        ("prosody_time", "REAL"), ("transcription_time", "REAL"), ("llm_time", "REAL"),
        ("injection_time", "REAL"), ("total_latency", "REAL"), ("engine", "TEXT"),
        ("mode", "TEXT"), ("status", "TEXT"), ("error_msg", "TEXT")
    ]
    /// Older schema's name for total_latency; kept filled so existing queries keep working
    private var hasLegacyTurnaroundColumn = false
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbPath = directory.appendingPathComponent("latency.db").path
        
        queue.async { self.setupDatabase() }
    }
    
    private func setupDatabase() {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            let createTableQuery = """
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
                clip_duration REAL,
                decode_time REAL,
                prosody_time REAL,
                transcription_time REAL,
                llm_time REAL,
                injection_time REAL,
                total_latency REAL,
                engine TEXT,
                mode TEXT,
                status TEXT,
                error_msg TEXT
            );
            """
            
            if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db)!)
                Logger.error("[LatencyTracker] Failed to create table: \(errmsg)")
            }
            
            // Migration: bring existing databases up to the expected schema
            let existing = existingColumns()
            for column in Self.expectedColumns where !existing.contains(column.name) {
                if sqlite3_exec(db, "ALTER TABLE metrics ADD COLUMN \(column.name) \(column.type);", nil, nil, nil) == SQLITE_OK {
                    Logger.info("[LatencyTracker] Added missing column '\(column.name)'")
                } else {
                    let errmsg = String(cString: sqlite3_errmsg(db)!)
                    Logger.error("[LatencyTracker] Failed to add column '\(column.name)': \(errmsg)")
                }
            }
            hasLegacyTurnaroundColumn = existing.contains("total_turnaround")
        } else {
            Logger.error("[LatencyTracker] Failed to open database at \(dbPath)")
        }
    }
    
    private func existingColumns() -> Set<String> {
        var names = Set<String>()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(metrics);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                // Column 1 of table_info is the column name
                if let name = sqlite3_column_text(stmt, 1) {
                    names.insert(String(cString: name))
                }
            }
        }
        sqlite3_finalize(stmt)
        return names
    }
    
    func record(
        sessionID: String,
        clipDuration: Double,
        decodeTime: Double,
        prosodyTime: Double,
        transcriptionTime: Double,
        llmTime: Double,
        injectionTime: Double,
        totalLatency: Double,
        engine: String,
        mode: String,
        status: String = "success",
        errorMessage: String? = nil
    ) {
        queue.async {
            self.insert(sessionID: sessionID, clipDuration: clipDuration, decodeTime: decodeTime,
                        prosodyTime: prosodyTime, transcriptionTime: transcriptionTime, llmTime: llmTime,
                        injectionTime: injectionTime, totalLatency: totalLatency, engine: engine,
                        mode: mode, status: status, errorMessage: errorMessage)
        }
    }
    
    private func insert(
        sessionID: String,
        clipDuration: Double,
        decodeTime: Double,
        prosodyTime: Double,
        transcriptionTime: Double,
        llmTime: Double,
        injectionTime: Double,
        totalLatency: Double,
        engine: String,
        mode: String,
        status: String,
        errorMessage: String?
    ) {
        let legacy = hasLegacyTurnaroundColumn
        let insertQuery = """
        INSERT INTO metrics (session_id, clip_duration, decode_time, prosody_time, transcription_time, llm_time, injection_time, total_latency, engine, mode, status, error_msg\(legacy ? ", total_turnaround" : ""))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?\(legacy ? ", ?" : ""));
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (sessionID as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, clipDuration)
            sqlite3_bind_double(stmt, 3, decodeTime)
            sqlite3_bind_double(stmt, 4, prosodyTime)
            sqlite3_bind_double(stmt, 5, transcriptionTime)
            sqlite3_bind_double(stmt, 6, llmTime)
            sqlite3_bind_double(stmt, 7, injectionTime)
            sqlite3_bind_double(stmt, 8, totalLatency)
            sqlite3_bind_text(stmt, 9, (engine as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 10, (mode as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 11, (status as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            if let errorMsg = errorMessage {
                sqlite3_bind_text(stmt, 12, (errorMsg as NSString).utf8String, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            if legacy {
                sqlite3_bind_double(stmt, 13, totalLatency)
            }
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db)!)
                Logger.error("[LatencyTracker] Failed to insert metric: \(errmsg)")
            }
        } else {
            let errmsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
            Logger.error("[LatencyTracker] Failed to prepare insert: \(errmsg)")
        }
        sqlite3_finalize(stmt)
    }
    
    deinit {
        sqlite3_close(db)
    }
}
