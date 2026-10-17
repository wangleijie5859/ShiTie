import AppKit
import CryptoKit
import SQLite3
import ShitieCore

final class HistoryTests {
    private var directories: [URL] = []
    func cleanup() { for directory in directories { try? FileManager.default.removeItem(at: directory) } }
    private func databaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shitie-tests-\(UUID())")
        directories.append(directory)
        return directory.appendingPathComponent("history.sqlite")
    }

    func testExactDuplicateMovesToTopAndPreservesMetadata() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        let firstTime = Date(timeIntervalSince1970: 10)
        let captured = try await repository.capture(" 代码\n    print(1)\n", at: firstTime)
        let id = try require(captured)
        let category = try await repository.saveCategory(name: "开发")
        try await repository.move(id: id, to: category)
        try await repository.capture("其他", at: Date(timeIntervalSince1970: 20))
        let repeatedID = try await repository.capture(" 代码\n    print(1)\n", at: Date(timeIntervalSince1970: 30))
        let snapshot = try await repository.snapshot()
        try expectEqual(repeatedID, id)
        try expectEqual(snapshot.totalCount, 2)
        try expectEqual(snapshot.clips.first?.id, id)
        try expectEqual(snapshot.clips.first?.createdAt, firstTime)
        try expectEqual(snapshot.clips.first?.lastCopiedAt, Date(timeIntervalSince1970: 30))
        try expectEqual(snapshot.clips.first?.categoryID, category)
        let detail = try await repository.detail(id: id)
        try expectEqual(detail?.content, " 代码\n    print(1)\n")
    }

    func testByteExactDeduplicationAndWhitespace() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        try await repository.capture("é")
        try await repository.capture("e\u{301}")
        try await repository.capture("é ")
        try await repository.capture("é")
        let emptyID = try await repository.capture(" \n\t")
        let snapshot = try await repository.snapshot()
        try expectNil(emptyID)
        try expectEqual(snapshot.totalCount, 3)
    }

    func testCategoryValidationAndDeletionMovesRecordsToUncategorized() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        let category = try await repository.saveCategory(name: "  Work  ")
        for name in ["", " \n ", "work", "Ｗｏｒｋ", "全部", "未分类", String(repeating: "a", count: 41)] {
            do { _ = try await repository.saveCategory(name: name); throw CheckFailure("Invalid or duplicate category accepted") }
            catch is HistoryError {} catch { throw CheckFailure("Unexpected error") }
        }
        try await repository.saveCategory(name: "工作资料", id: category)
        let captured = try await repository.capture("分类内容")
        let id = try require(captured)
        try await repository.move(id: id, to: category)
        try await repository.deleteCategory(id: category)
        let snapshot = try await repository.snapshot(filter: .uncategorized)
        try expect(snapshot.categories.isEmpty)
        try expectEqual(snapshot.clips.map(\.id), [id])
        try expectNil(snapshot.clips.first?.categoryID)
        try expectEqual(try await repository.detail(id: id)?.content, "分类内容")
        let customID = try await repository.saveCategory(name: "收藏")
        try await repository.move(id: id, to: customID)
        let custom = try await repository.snapshot(filter: .category(customID))
        try expectEqual(custom.clips.map(\.id), [id])
    }

    func testPersistenceAcrossIndependentConnections() async throws {
        let url = databaseURL()
        let repository = try HistoryRepository(url: url)
        let category = try await repository.saveCategory(name: "稍后阅读")
        let captured = try await repository.capture("https://example.com/中文?q=Swift")
        let id = try require(captured)
        try await repository.move(id: id, to: category)
        try await repository.setLimit(42)
        try await repository.setPaused(true)
        let reopened = try HistoryRepository(url: url)
        let snapshot = try await reopened.snapshot(filter: .category(category))
        let detail = try await reopened.detail(id: id)
        try expectEqual(snapshot.clips.map(\.id), [id])
        try expectEqual(snapshot.categories.first?.name, "稍后阅读")
        try expectEqual(snapshot.settings.limit, 42)
        try expect(snapshot.settings.isPaused)
        try expectEqual(detail?.content, "https://example.com/中文?q=Swift")
    }

    func testSearchChineseEnglishURLAndLiteralPunctuationWithinFilter() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        let category = try await repository.saveCategory(name: "资料")
        let captured = try await repository.capture("中文 Swift 资料 https://example.com/a?q=100%_done")
        let id = try require(captured)
        try await repository.move(id: id, to: category)
        try await repository.capture("另一个 swift 内容")
        for query in ["中文", "SWIFT", "example.com", "100%_done"] {
            let snapshot = try await repository.snapshot(filter: .category(category), search: query)
            try expectEqual(snapshot.clips.map(\.id), [id])
        }
        let all = try await repository.snapshot(search: "swift")
        let absent = try await repository.snapshot(filter: .category(category), search: "不存在")
        try expectEqual(all.clips.count, 2)
        try expect(absent.clips.isEmpty)
    }

    func testLimitEvictsOldestByLastCopyTime() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        try await repository.setLimit(3)
        try await repository.capture("最早", at: Date(timeIntervalSince1970: 1))
        try await repository.capture("旧", at: Date(timeIntervalSince1970: 2))
        try await repository.capture("新", at: Date(timeIntervalSince1970: 3))
        try await repository.capture("旧", at: Date(timeIntervalSince1970: 4))
        try await repository.capture("最新", at: Date(timeIntervalSince1970: 5))
        let snapshot = try await repository.snapshot()
        try expectEqual(snapshot.clips.map(\.preview), ["最新", "旧", "新"])
        try await repository.setLimit(1)
        let reduced = try await repository.snapshot()
        try expectEqual(reduced.clips.map(\.preview), ["最新"])
    }

    func testVersionTwoMigrationPreservesContentAndUnifiesCleanup() async throws {
        let url = databaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        try expectEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        let contents = ["legacy one", "legacy two", "legacy three"]
        let inserts = contents.enumerated().map { index, content in
            let digest = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
            return "INSERT INTO clips VALUES (\(index + 1), '\(content)', '\(digest)', 'text', \(index + 1), \((index + 1) * 10), 1, \(index == 1 ? 0 : 1), \(content.utf8.count));"
        }.joined(separator: "\n")
        let legacySchema = """
        CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE, color TEXT NOT NULL);
        INSERT INTO categories VALUES (1, '旧分类', '旧分类', 'purple');
        CREATE TABLE clips (id INTEGER PRIMARY KEY, content TEXT NOT NULL, digest TEXT NOT NULL,
            kind TEXT NOT NULL, created_at REAL NOT NULL, copied_at REAL NOT NULL,
            category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
            favorite INTEGER NOT NULL DEFAULT 0, byte_count INTEGER NOT NULL);
        \(inserts)
        CREATE TABLE settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        INSERT INTO settings VALUES ('paused', 1), ('limit', 1);
        PRAGMA user_version = 2;
        """
        try expectEqual(sqlite3_exec(connection, legacySchema, nil, nil, nil), SQLITE_OK)
        let repository = try HistoryRepository(url: url)
        let snapshot = try await repository.snapshot()
        try expectEqual(snapshot.clips.map(\.id), [3, 2, 1])
        try expectEqual(snapshot.settings, HistorySettings(isPaused: true, limit: 1))
        try expectEqual(snapshot.categories.first?.color, .purple)
        for index in contents.indices {
            let detail = try await repository.detail(id: Int64(index + 1))
            try expectEqual(detail?.content, contents[index])
            try expectEqual(detail?.summary.categoryID, 1)
            try expectEqual(detail?.summary.createdAt, Date(timeIntervalSince1970: Double(index + 1)))
            try expectEqual(detail?.summary.lastCopiedAt, Date(timeIntervalSince1970: Double((index + 1) * 10)))
        }
        var query: OpaquePointer?
        try expectEqual(sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &query, nil), SQLITE_OK)
        try expectEqual(sqlite3_step(query), SQLITE_ROW)
        try expectEqual(sqlite3_column_int(query, 0), 3)
        sqlite3_finalize(query)
        query = nil
        try expectEqual(sqlite3_prepare_v2(connection, "SELECT count(*) FROM pragma_table_info('clips') WHERE name = 'favorite'", -1, &query, nil), SQLITE_OK)
        try expectEqual(sqlite3_step(query), SQLITE_ROW)
        try expectEqual(sqlite3_column_int(query, 0), 0)
        sqlite3_finalize(query)
        let reopened = try HistoryRepository(url: url)
        try expectEqual(try await reopened.snapshot().totalCount, 3)
        try await repository.setPaused(false)
        try await repository.capture("latest", at: Date(timeIntervalSince1970: 40))
        try expectEqual(try await repository.snapshot().clips.map(\.preview), ["latest"])
        try await repository.clear()
        let cleared = try await repository.snapshot()
        try expectEqual(cleared.totalCount, 0)
        try expectEqual(cleared.categories.first?.color, .purple)

        // A failed migration must roll back the original table and schema version.
        let blockedURL = databaseURL()
        try FileManager.default.createDirectory(at: blockedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var blocked: OpaquePointer?
        try expectEqual(sqlite3_open(blockedURL.path, &blocked), SQLITE_OK)
        defer { sqlite3_close(blocked) }
        let blocker = "CREATE TABLE migration_guard (clip_id INTEGER REFERENCES clips(id) ON DELETE RESTRICT); INSERT INTO migration_guard VALUES (1);"
        try expectEqual(sqlite3_exec(blocked, legacySchema + blocker, nil, nil, nil), SQLITE_OK)
        do { _ = try HistoryRepository(url: blockedURL); throw CheckFailure("Blocked migration unexpectedly succeeded") }
        catch is HistoryError {}
        query = nil
        try expectEqual(sqlite3_prepare_v2(blocked, "SELECT count(*), sum(favorite), (SELECT user_version FROM pragma_user_version), (SELECT count(*) FROM sqlite_master WHERE name = 'clips_v3') FROM clips", -1, &query, nil), SQLITE_OK)
        defer { sqlite3_finalize(query) }
        try expectEqual(sqlite3_step(query), SQLITE_ROW)
        try expectEqual(sqlite3_column_int(query, 0), 3)
        try expectEqual(sqlite3_column_int(query, 1), 2)
        try expectEqual(sqlite3_column_int(query, 2), 2)
        try expectEqual(sqlite3_column_int(query, 3), 0)
    }

    func testClearRemovesAllHistoryAndPreservesCategories() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        try await repository.saveCategory(name: "保留分类")
        try await repository.capture("内容一")
        try await repository.capture("内容二")
        try await repository.clear()
        let empty = try await repository.snapshot()
        try expectEqual(empty.totalCount, 0)
        try expectEqual(empty.categories.count, 1)
    }

    func testPauseAndSizeBoundary() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        try await repository.setPaused(true)
        let pausedID = try await repository.capture("暂停内容")
        try expectNil(pausedID)
        try await repository.setPaused(false)
        let content = String(repeating: "a", count: HistoryRepository.maximumTextBytes)
        let captured = try await repository.capture(content)
        let id = try require(captured)
        let detail = try await repository.detail(id: id)
        try expectEqual(detail?.content, content)
        do { try await repository.capture(content + "a"); throw CheckFailure("Oversized text accepted") }
        catch HistoryError.tooLarge {} catch { throw CheckFailure("Unexpected error") }
        do { try await repository.capture("a\0b"); throw CheckFailure("NUL text accepted") }
        catch HistoryError.invalidText {} catch { throw CheckFailure("Unexpected error") }
    }

    func testLinkDetectionOnlyAcceptsCompleteHTTPURLs() throws {
        for link in ["https://example.com", " HTTP://example.com/a?q=中文#part\n", "https://例子.测试/路径"] {
            try expectEqual(ClipKind.detect(link), .link)
        }
        for text in ["example.com", "hello https://example.com", "https://", "file:///tmp/a", "javascript:alert(1)", "https://example.com/a b"] {
            try expectEqual(ClipKind.detect(text), .text)
        }
    }

    @MainActor func testClipboardChangeCountPauseSensitiveTypesAndSelfCopy() throws {
        let pasteboard = NSPasteboard(name: .init("local.shitie.tests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        var events: [String] = []
        var oversizeCount = 0
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { event in
            switch event {
            case .text(let content): events.append(content)
            case .oversized: oversizeCount += 1
            case .unsupportedText: break
            }
        }
        pasteboard.setString("启动前", forType: .string)
        monitor.start(paused: false)
        defer { monitor.stop() }
        monitor.poll()
        try expect(events.isEmpty)
        func write(_ text: String) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        write("普通文字")
        monitor.poll(); monitor.poll()
        try expectEqual(events, ["普通文字"])
        write("https://example.com")
        monitor.poll()
        try expectEqual(ClipKind.detect(events.last ?? ""), .link)
        try expect(monitor.copy("应用内复制"))
        monitor.poll()
        try expectEqual(events.count, 2)
        monitor.setPaused(true)
        write("暂停期间")
        monitor.poll()
        write("恢复前未轮询的内容")
        monitor.setPaused(false)
        monitor.poll()
        try expectEqual(events.count, 2)
        write("恢复后")
        monitor.poll()
        try expectEqual(events.last, "恢复后")
        for type in PasteboardMonitor.excludedTypes.union(["com.agilebits.onepassword.custom", "NSFilenamesPboardType", "public.jpeg", NSPasteboard.PasteboardType.fileURL.rawValue, NSPasteboard.PasteboardType.png.rawValue]) {
            write("不应读取")
            pasteboard.setData(Data(), forType: .init(type))
            monitor.poll()
        }
        try expectEqual(events.count, 3)
        write(" \n\t")
        monitor.poll()
        try expectEqual(events.count, 3)
        write(String(repeating: "a", count: HistoryRepository.maximumTextBytes + 1))
        monitor.poll()
        try expectEqual(oversizeCount, 1)
        try expectEqual(events.count, 3)
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/url-only", forType: .URL)
        monitor.poll()
        try expectEqual(events.last, "https://example.com/url-only")
        write("来源元信息不是敏感标记")
        pasteboard.setString("local.shitie.tests", forType: .init("org.nspasteboard.source"))
        monitor.poll()
        try expectEqual(events.last, "来源元信息不是敏感标记")
    }

    @MainActor func testActualPollingTimerReceivesText() async throws {
        let pasteboard = NSPasteboard(name: .init("local.shitie.timer-tests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        var received: String?
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { if case .text(let value) = $0 { received = value } }
        monitor.start(paused: false)
        defer { monitor.stop() }
        pasteboard.clearContents()
        pasteboard.setString("定时监听验证", forType: .string)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try expectEqual(received, "定时监听验证")
    }

    func testFailedDatabaseOpenReportsError() throws {
        let directory = databaseURL().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do { _ = try HistoryRepository(url: directory); throw CheckFailure("Database open unexpectedly succeeded") }
        catch is HistoryError {}
    }

    func testFailedCapacityChangeRollsBackAndNewerSchemaIsPreserved() async throws {
        let url = databaseURL()
        let repository = try HistoryRepository(url: url)
        try await repository.capture("first")
        try await repository.capture("second")
        var connection: OpaquePointer?
        try expectEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        let trigger = "CREATE TRIGGER block_cleanup BEFORE DELETE ON clips BEGIN SELECT RAISE(ABORT, 'test'); END;"
        try expectEqual(sqlite3_exec(connection, trigger, nil, nil, nil), SQLITE_OK)
        do { try await repository.setLimit(1); throw CheckFailure("Failed cleanup unexpectedly succeeded") }
        catch is HistoryError {}
        let snapshot = try await repository.snapshot()
        try expectEqual(snapshot.settings.limit, 1000)
        try expectEqual(snapshot.totalCount, 2)
        try expectEqual(sqlite3_exec(connection, "PRAGMA user_version = 99", nil, nil, nil), SQLITE_OK)
        do { _ = try HistoryRepository(url: url); throw CheckFailure("Newer schema unexpectedly accepted") }
        catch is HistoryError {}
        var query: OpaquePointer?
        try expectEqual(sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &query, nil), SQLITE_OK)
        defer { sqlite3_finalize(query) }
        try expectEqual(sqlite3_step(query), SQLITE_ROW)
        try expectEqual(sqlite3_column_int(query, 0), 99)
    }

    func testEditingPreservesMetadataUpdatesTypeAndDeduplication() async throws {
        let url = databaseURL()
        let repository = try HistoryRepository(url: url)
        let created = Date(timeIntervalSince1970: 10)
        let captured = try await repository.capture("原始文本\n    缩进", at: created)
        let id = try require(captured)
        let category = try await repository.saveCategory(name: "开发", color: .purple)
        try await repository.move(id: id, to: category)
        try await repository.setPaused(true)
        let edited = "https://example.com/edited?q=中文"
        try await repository.edit(id: id, content: edited)
        let detail = try await repository.detail(id: id)
        try expectEqual(detail?.content, edited)
        try expectEqual(detail?.summary.kind, .link)
        try expectEqual(detail?.summary.createdAt, created)
        try expectEqual(detail?.summary.lastCopiedAt, created)
        try expectEqual(detail?.summary.categoryID, category)
        try expectEqual(detail?.summary.byteCount, edited.utf8.count)
        let oldSearch = try await repository.snapshot(search: "原始文本")
        let newSearch = try await repository.snapshot(search: "edited")
        try expect(oldSearch.clips.isEmpty)
        try expectEqual(newSearch.clips.map(\.id), [id])
        let reopened = try HistoryRepository(url: url)
        let reloaded = try await reopened.detail(id: id)
        try expectEqual(reloaded?.content, edited)
        try await repository.setPaused(false)
        let repeated = try await repository.capture(edited)
        try expectEqual(repeated, id)
        try await repository.capture("原始文本\n    缩进")
        let snapshot = try await repository.snapshot()
        try expectEqual(snapshot.totalCount, 2)
        try await repository.edit(id: id, content: "代码\n    print(1)\n")
        let code = try await repository.detail(id: id)
        try expectEqual(code?.summary.kind, .text)
        try expectEqual(code?.content, "代码\n    print(1)\n")
    }

    func testInvalidAndDuplicateEditsLeaveOriginalRecordsIntact() async throws {
        let repository = try HistoryRepository(url: databaseURL())
        let captured = try await repository.capture("第一条")
        let id = try require(captured)
        try await repository.capture("第二条")
        for value in [" \n\t", "a\0b", String(repeating: "a", count: HistoryRepository.maximumTextBytes + 1), "第二条"] {
            do { try await repository.edit(id: id, content: value); throw CheckFailure("Invalid edit accepted") }
            catch is HistoryError {}
            let original = try await repository.detail(id: id)
            let snapshot = try await repository.snapshot()
            try expectEqual(original?.content, "第一条")
            try expectEqual(snapshot.totalCount, 2)
        }
        try await repository.edit(id: id, content: "第一条")
        do { try await repository.edit(id: -1, content: "已删除记录"); throw CheckFailure("Missing clip edit accepted") }
        catch HistoryError.missingClip {}
        try await repository.capture("e\u{301}")
        try await repository.edit(id: id, content: "é")
        let exact = try await repository.detail(id: id)
        try expectEqual(exact?.content.utf8.map { $0 }, Array("é".utf8))
    }

    func testCategoryColorsPersistAndRenamingPreservesColor() async throws {
        let url = databaseURL()
        let repository = try HistoryRepository(url: url)
        let first = try await repository.saveCategory(name: "生活", color: .pink)
        let second = try await repository.saveCategory(name: "工作")
        try await repository.saveCategory(name: "生活资料", id: first)
        var snapshot = try await repository.snapshot()
        try expectEqual(snapshot.categories.first { $0.id == first }?.color, .pink)
        try expectEqual(snapshot.categories.first { $0.id == second }?.color, .teal)
        try await repository.saveCategory(name: "生活资料", id: first, color: .green)
        let reopened = try HistoryRepository(url: url)
        snapshot = try await reopened.snapshot()
        try expectEqual(snapshot.categories.first { $0.id == first }?.color, .green)
        try expectEqual(snapshot.categories.first { $0.id == first }?.name, "生活资料")
        try expectEqual(snapshot.categories.first { $0.id == second }?.color, .teal)
    }

    func testVersionOneMigrationPreservesExistingHistoryAndAssignsColors() async throws {
        let url = databaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        try expectEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        let digest = SHA256.hash(data: Data("legacy text".utf8)).map { String(format: "%02x", $0) }.joined()
        let legacySchema = """
        CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE);
        INSERT INTO categories VALUES (1, '旧分类一', '旧分类一'), (2, '旧分类二', '旧分类二');
        CREATE TABLE clips (id INTEGER PRIMARY KEY, content TEXT NOT NULL, digest TEXT NOT NULL,
            kind TEXT NOT NULL, created_at REAL NOT NULL, copied_at REAL NOT NULL,
            category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
            favorite INTEGER NOT NULL DEFAULT 0, byte_count INTEGER NOT NULL);
        INSERT INTO clips VALUES (1, 'legacy text', '\(digest)', 'text', 10, 20, 2, 1, 11);
        CREATE TABLE settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        INSERT INTO settings VALUES ('paused', 1), ('limit', 12);
        PRAGMA user_version = 1;
        """
        try expectEqual(sqlite3_exec(connection, legacySchema, nil, nil, nil), SQLITE_OK)
        let repository = try HistoryRepository(url: url)
        let snapshot = try await repository.snapshot()
        let detail = try await repository.detail(id: 1)
        try expectEqual(snapshot.categories.map(\.color), [.teal, .blue])
        try expectEqual(snapshot.categories.map(\.name), ["旧分类一", "旧分类二"])
        try expectEqual(detail?.content, "legacy text")
        try expectEqual(detail?.summary.categoryID, 2)
        try expectEqual(detail?.summary.createdAt, Date(timeIntervalSince1970: 10))
        try expectEqual(detail?.summary.lastCopiedAt, Date(timeIntervalSince1970: 20))
        try expectEqual(snapshot.settings, HistorySettings(isPaused: true, limit: 12))
        try await repository.setPaused(false)
        let repeated = try await repository.capture("legacy text")
        try expectEqual(repeated, 1)
        let reopened = try HistoryRepository(url: url)
        let reloaded = try await reopened.snapshot()
        try expectEqual(reloaded.totalCount, 1)
        try expectEqual(reloaded.categories.map(\.color), [.teal, .blue])
    }
}
