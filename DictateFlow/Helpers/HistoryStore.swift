import Foundation
import SQLite3

actor HistoryStore {
    enum StoreError: LocalizedError {
        case databaseOpenFailed(String)
        case sqlError(String)
        case notInitialized

        var errorDescription: String? {
            switch self {
            case let .databaseOpenFailed(message):
                return message
            case let .sqlError(message):
                return message
            case .notInitialized:
                return "Der lokale Verlaufsspeicher konnte nicht initialisiert werden."
            }
        }
    }

    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var initializationError: Error?
    private var didInitialize = false

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func fetchAll() throws -> [Transcription] {
        try initializeIfNeeded()

        let sql = """
        SELECT id, created_at, profile, raw_text, processed_text
        FROM transcriptions
        ORDER BY created_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        var results: [Transcription] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idCString = sqlite3_column_text(statement, 0),
                let profileCString = sqlite3_column_text(statement, 2),
                let rawCString = sqlite3_column_text(statement, 3),
                let processedCString = sqlite3_column_text(statement, 4)
            else {
                continue
            }

            let idString = String(cString: idCString)
            guard let id = UUID(uuidString: idString) else { continue }

            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let profile = Profile(rawValue: String(cString: profileCString)) ?? .meetingNote
            let rawText = String(cString: rawCString)
            let processedText = String(cString: processedCString)

            let item = Transcription(
                id: id,
                createdAt: createdAt,
                profile: profile,
                rawText: rawText,
                processedText: processedText
            )

            results.append(item)
        }

        return results
    }

    func insert(_ transcription: Transcription) throws {
        try initializeIfNeeded()

        let sql = """
        INSERT INTO transcriptions (id, created_at, profile, raw_text, processed_text)
        VALUES (?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        bindText(transcription.id.uuidString, at: 1, statement: statement)
        sqlite3_bind_double(statement, 2, transcription.createdAt.timeIntervalSince1970)
        bindText(transcription.profile.rawValue, at: 3, statement: statement)
        bindText(transcription.rawText, at: 4, statement: statement)
        bindText(transcription.processedText, at: 5, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func update(_ transcription: Transcription) throws {
        try initializeIfNeeded()

        let sql = """
        UPDATE transcriptions
        SET profile = ?, processed_text = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        bindText(transcription.profile.rawValue, at: 1, statement: statement)
        bindText(transcription.processedText, at: 2, statement: statement)
        bindText(transcription.id.uuidString, at: 3, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func delete(id: UUID) throws {
        try initializeIfNeeded()

        let sql = "DELETE FROM transcriptions WHERE id = ?;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        bindText(id.uuidString, at: 1, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    private func initializeIfNeeded() throws {
        if didInitialize { return }
        if let initializationError {
            throw initializationError
        }

        do {
            try openDatabase()
            try createTableIfNeeded()
            didInitialize = true
        } catch {
            initializationError = error
            throw error
        }
    }

    private func openDatabase() throws {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let folderURL = appSupport.appendingPathComponent("DictateFlow", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let dbURL = folderURL.appendingPathComponent("history.sqlite")

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            throw StoreError.databaseOpenFailed("SQLite konnte nicht geöffnet werden: \(dbURL.path)")
        }
    }

    private func createTableIfNeeded() throws {
        let createSQL = """
        CREATE TABLE IF NOT EXISTS transcriptions (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            profile TEXT NOT NULL,
            raw_text TEXT NOT NULL,
            processed_text TEXT NOT NULL
        );
        """

        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, createSQL, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unbekannter SQLite-Fehler"
            sqlite3_free(errorMessage)
            throw StoreError.sqlError(message)
        }
    }

    private func bindText(_ text: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, (text as NSString).utf8String, -1, transient)
    }

    private func lastError() -> StoreError {
        let message: String
        if let db, let cString = sqlite3_errmsg(db) {
            message = String(cString: cString)
        } else {
            message = "Unbekannter SQLite-Fehler"
        }

        return .sqlError(message)
    }
}
