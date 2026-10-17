import CryptoKit
import Foundation
import SQLite3

/// All database access, hashing, filtering and capacity cleanup runs on this actor.
public actor HistoryRepository {
    public static let maximumTextBytes = 1_048_576
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shitie", isDirectory: true).appendingPathComponent("history.sqlite")
    }

    private let db: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let directoryExists = FileManager.default.fileExists(atPath: directory.path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Protect the directory and all SQLite sidecars from other local users.
        if !directoryExists {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let connection else {
            if let connection { sqlite3_close(connection) }
            throw HistoryError.database("无法打开数据文件，请检查磁盘空间与访问权限。")
        }
        sqlite3_busy_timeout(connection, 3_000)
        var versionQuery: OpaquePointer?
        let prepared = sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &versionQuery, nil)
        let version = prepared == SQLITE_OK && sqlite3_step(versionQuery) == SQLITE_ROW ? sqlite3_column_int(versionQuery, 0) : -1
        sqlite3_finalize(versionQuery)
        guard version >= 0, version <= 3 else {
            sqlite3_close(connection)
            throw HistoryError.database("数据格式来自更新版本或无法读取，请保留数据文件并使用兼容版本。")
        }
        let colorMigration = version < 2 ? """
        ALTER TABLE categories ADD COLUMN color TEXT NOT NULL DEFAULT 'teal';
        UPDATE categories SET color = CASE abs(id - 1) % 8
            WHEN 0 THEN 'teal' WHEN 1 THEN 'blue' WHEN 2 THEN 'purple' WHEN 3 THEN 'pink'
            WHEN 4 THEN 'orange' WHEN 5 THEN 'green' WHEN 6 THEN 'red' ELSE 'gray' END;
        """ : ""
        let clipColumns = """
            id INTEGER PRIMARY KEY, content TEXT NOT NULL, digest TEXT NOT NULL,
            kind TEXT NOT NULL, created_at REAL NOT NULL, copied_at REAL NOT NULL,
            category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
            byte_count INTEGER NOT NULL
        """
        // Upgrade without deleting any history, even if an old database exceeds its limit.
        let clipMigration = (1...2).contains(version) ? """
        CREATE TABLE clips_v3 (\(clipColumns));
        INSERT INTO clips_v3 (id, content, digest, kind, created_at, copied_at, category_id, byte_count)
            SELECT id, content, digest, kind, created_at, copied_at, category_id, byte_count FROM clips;
        DROP TABLE clips;
        ALTER TABLE clips_v3 RENAME TO clips;
        """ : ""
        let schema = """
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;
        PRAGMA secure_delete = ON;
        PRAGMA synchronous = FULL;
        BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS clips (\(clipColumns));
        \(clipMigration)
        CREATE INDEX IF NOT EXISTS clips_digest ON clips(digest);
        CREATE INDEX IF NOT EXISTS clips_copied ON clips(copied_at DESC, id DESC);
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        INSERT OR IGNORE INTO settings VALUES ('paused', 0), ('limit', 1000);
        \(colorMigration)
        PRAGMA user_version = 3;
        COMMIT;
        """
        guard sqlite3_exec(connection, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            throw HistoryError.database("无法初始化数据文件。原文件未被替换。")
        }
        db = connection
    }

    deinit { sqlite3_close(db) }

    private enum Value {
        case text(String), integer(Int64), real(Double), null
    }

    private func statement(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw databaseError()
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let text): status = sqlite3_bind_text(pointer, index, text, -1, transient)
            case .integer(let number): status = sqlite3_bind_int64(pointer, index, number)
            case .real(let number): status = sqlite3_bind_double(pointer, index, number)
            case .null: status = sqlite3_bind_null(pointer, index)
            }
            guard status == SQLITE_OK else {
                sqlite3_finalize(pointer)
                throw databaseError()
            }
        }
        return pointer
    }

    private func databaseError() -> HistoryError {
        // Do not expose SQL or clipboard content in diagnostics.
        .database("\(String(cString: sqlite3_errstr(sqlite3_errcode(db))))（\(sqlite3_errcode(db))）")
    }

    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let query = try statement(sql, values)
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_DONE else { throw databaseError() }
    }

    private func rows<T>(_ sql: String, _ values: [Value] = [], map: (OpaquePointer) -> T) throws -> [T] {
        let query = try statement(sql, values)
        defer { sqlite3_finalize(query) }
        var result: [T] = []
        while true {
            switch sqlite3_step(query) {
            case SQLITE_ROW: result.append(map(query))
            case SQLITE_DONE: return result
            default: throw databaseError()
            }
        }
    }

    private func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try work()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func string(_ row: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(row, column) else { return "" }
        return String(cString: bytes)
    }

    private var summaryColumns: String {
        "id, substr(content, 1, 240), kind, created_at, copied_at, category_id, byte_count"
    }

    private func summary(_ row: OpaquePointer) -> ClipSummary {
        ClipSummary(id: sqlite3_column_int64(row, 0), preview: string(row, 1),
                    kind: ClipKind(rawValue: string(row, 2)) ?? .text,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 3)),
                    lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 4)),
                    categoryID: sqlite3_column_type(row, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(row, 5),
                    byteCount: Int(sqlite3_column_int64(row, 6)))
    }

    public func settings() throws -> HistorySettings {
        let pairs = try rows("SELECT key, value FROM settings") { (string($0, 0), Int(sqlite3_column_int64($0, 1))) }
        let values = Dictionary(uniqueKeysWithValues: pairs)
        return HistorySettings(isPaused: values["paused"] == 1, limit: values["limit"] ?? 1000)
    }

    public func snapshot(filter: ClipFilter = .all, search: String = "") throws -> HistorySnapshot {
        var conditions: [String] = []
        var values: [Value] = []
        switch filter {
        case .all: break
        case .uncategorized: conditions.append("category_id IS NULL")
        case .category(let id): conditions.append("category_id = ?"); values.append(.integer(id))
        }
        if !search.isEmpty {
            // ponytail: linear substring scan; index it only if large histories make search too slow.
            // instr treats %, _ and URL punctuation literally. SQLite lower covers English; Chinese is unchanged.
            conditions.append("instr(lower(content), lower(?)) > 0")
            values.append(.text(search))
        }
        let clause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        let clips = try rows("SELECT \(summaryColumns) FROM clips\(clause) ORDER BY copied_at DESC, id DESC", values, map: summary)
        let categories = try rows("SELECT id, name, color FROM categories ORDER BY id") {
            ClipCategory(id: sqlite3_column_int64($0, 0), name: string($0, 1), color: CategoryColor(rawValue: string($0, 2)) ?? .teal)
        }
        let total = try rows("SELECT count(*) FROM clips") { Int(sqlite3_column_int64($0, 0)) }[0]
        return HistorySnapshot(clips: clips, categories: categories, settings: try settings(), totalCount: total)
    }

    public func detail(id: Int64) throws -> ClipDetail? {
        try rows("SELECT \(summaryColumns), content FROM clips WHERE id = ?", [.integer(id)]) {
            ClipDetail(summary: summary($0), content: string($0, 7))
        }.first
    }

    @discardableResult
    public func capture(_ content: String, at date: Date = Date()) throws -> Int64? {
        guard !(try settings()).isPaused else { return nil }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let byteCount = try validatedByteCount(content)
        let digest = contentDigest(content)
        return try transaction {
            let id: Int64
            if let existing = try matchingID(content: content, digest: digest) {
                id = existing
                try execute("UPDATE clips SET copied_at = ? WHERE id = ?", [.real(date.timeIntervalSince1970), .integer(id)])
            } else {
                try execute("INSERT INTO clips (content, digest, kind, created_at, copied_at, byte_count) VALUES (?, ?, ?, ?, ?, ?)",
                            [.text(content), .text(digest), .text(ClipKind.detect(content).rawValue), .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970), .integer(Int64(byteCount))])
                id = sqlite3_last_insert_rowid(db)
            }
            try enforceLimit()
            return id
        }
    }

    public func edit(id: Int64, content: String) throws {
        let byteCount = try validatedByteCount(content)
        let digest = contentDigest(content)
        try transaction {
            let exists = try rows("SELECT id FROM clips WHERE id = ?", [.integer(id)]) { sqlite3_column_int64($0, 0) }
            guard !exists.isEmpty else { throw HistoryError.missingClip }
            if let duplicate = try matchingID(content: content, digest: digest), duplicate != id {
                throw HistoryError.duplicateContent
            }
            // Editing keeps classification, creation time and actual copy time intact.
            try execute("UPDATE clips SET content = ?, digest = ?, kind = ?, byte_count = ? WHERE id = ?",
                        [.text(content), .text(digest), .text(ClipKind.detect(content).rawValue), .integer(Int64(byteCount)), .integer(id)])
        }
    }

    private func validatedByteCount(_ content: String) throws -> Int {
        let byteCount = content.utf8.count
        guard byteCount <= Self.maximumTextBytes else { throw HistoryError.tooLarge }
        guard !content.contains("\0") else { throw HistoryError.invalidText }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HistoryError.emptyContent }
        return byteCount
    }

    private func contentDigest(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func matchingID(content: String, digest: String) throws -> Int64? {
        let candidates = try rows("SELECT id, content FROM clips WHERE digest = ?", [.text(digest)]) { (sqlite3_column_int64($0, 0), string($0, 1)) }
        return candidates.first(where: { $0.1.utf8.elementsEqual(content.utf8) })?.0
    }

    public func markCopied(id: Int64, at date: Date = Date()) throws {
        try execute("UPDATE clips SET copied_at = ? WHERE id = ?", [.real(date.timeIntervalSince1970), .integer(id)])
    }

    public func move(id: Int64, to categoryID: Int64?) throws {
        try execute("UPDATE clips SET category_id = ? WHERE id = ?", [categoryID.map(Value.integer) ?? .null, .integer(id)])
    }

    public func delete(id: Int64) throws { try execute("DELETE FROM clips WHERE id = ?", [.integer(id)]) }

    public func clear() throws { try execute("DELETE FROM clips") }

    @discardableResult
    public func saveCategory(name: String, id: Int64? = nil, color: CategoryColor? = nil) throws -> Int64 {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw HistoryError.invalidCategory("分类名称不能为空。") }
        guard name.count <= 40 else { throw HistoryError.invalidCategory("分类名称最多 40 个字符。") }
        guard !name.contains("\0") else { throw HistoryError.invalidCategory("分类名称包含无效字符。") }
        let key = name.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN")).precomposedStringWithCanonicalMapping
        guard !["全部", "未分类"].contains(key) else { throw HistoryError.invalidCategory("请使用与系统入口不同的名称。") }
        let duplicates = try rows("SELECT id FROM categories WHERE name_key = ?", [.text(key)]) { sqlite3_column_int64($0, 0) }
        guard duplicates.allSatisfy({ $0 == id }) else { throw HistoryError.invalidCategory("这个分类名称已经存在。") }
        if let id {
            try execute("UPDATE categories SET name = ?, name_key = ?, color = coalesce(?, color) WHERE id = ?", [.text(name), .text(key), color.map { .text($0.rawValue) } ?? .null, .integer(id)])
            return id
        }
        let usedColors = try rows("SELECT color FROM categories") { CategoryColor(rawValue: string($0, 0)) ?? .teal }
        let chosenColor = color ?? CategoryColor.suggested(excluding: usedColors)
        try execute("INSERT INTO categories (name, name_key, color) VALUES (?, ?, ?)", [.text(name), .text(key), .text(chosenColor.rawValue)])
        return sqlite3_last_insert_rowid(db)
    }

    public func deleteCategory(id: Int64) throws {
        try execute("DELETE FROM categories WHERE id = ?", [.integer(id)])
    }

    public func setPaused(_ paused: Bool) throws {
        try execute("UPDATE settings SET value = ? WHERE key = 'paused'", [.integer(paused ? 1 : 0)])
    }

    public func setLimit(_ limit: Int) throws {
        guard (1...100_000).contains(limit) else { throw HistoryError.invalidLimit }
        try transaction {
            try execute("UPDATE settings SET value = ? WHERE key = 'limit'", [.integer(Int64(limit))])
            try enforceLimit()
        }
    }

    private func enforceLimit() throws {
        let limit = try settings().limit
        try execute("""
            DELETE FROM clips WHERE id IN (
                SELECT id FROM clips ORDER BY copied_at ASC, id ASC
                LIMIT max(0, (SELECT count(*) FROM clips) - ?))
            """, [.integer(Int64(limit))])
    }
}
