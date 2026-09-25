import Foundation
import SQLite3

/// A persistent tracker for application performance metrics using SQLite.
class LatencyTracker {
    static let shared = LatencyTracker()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
        dbPath = directory.appendingPathComponent("latency.db").path
        
        setupDatabase()
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
                mode TEXT
            );
            """
            
            if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db)!)
                print("error creating table: \(errmsg)")
            }
            
            // Migration: Add mode column if it doesn't exist (for existing DBs)
            // We blindly attempt to add it; if it exists, it will fail harmlessly
            // Ensure schema is updated
            let _ = sqlite3_exec(db, "ALTER TABLE metrics ADD COLUMN mode TEXT;", nil, nil, nil)
            let _ = sqlite3_exec(db, "ALTER TABLE metrics ADD COLUMN status TEXT;", nil, nil, nil)
            let _ = sqlite3_exec(db, "ALTER TABLE metrics ADD COLUMN error_msg TEXT;", nil, nil, nil)
            
        } else {
            print("error opening database")
        }
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
        let insertQuery = """
        INSERT INTO metrics (session_id, clip_duration, decode_time, prosody_time, transcription_time, llm_time, injection_time, total_turnaround, engine, mode, status, error_msg)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (sessionID as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, clipDuration)
            sqlite3_bind_double(stmt, 3, decodeTime)
            sqlite3_bind_double(stmt, 4, prosodyTime)
            sqlite3_bind_double(stmt, 5, transcriptionTime)
            sqlite3_bind_double(stmt, 6, llmTime)
            sqlite3_bind_double(stmt, 7, injectionTime)
            sqlite3_bind_double(stmt, 8, totalLatency)
            sqlite3_bind_text(stmt, 9, (engine as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 10, (mode as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 11, (status as NSString).utf8String, -1, nil)
            
            if let errorMsg = errorMessage {
                sqlite3_bind_text(stmt, 12, (errorMsg as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db)!)
                print("failure inserting metric: \(errmsg)")
            }
        }
        sqlite3_finalize(stmt)
    }
    
    deinit {
        sqlite3_close(db)
    }
}
