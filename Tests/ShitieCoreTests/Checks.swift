import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #fileID, line: UInt = #line) throws {
    guard condition() else { throw CheckFailure("Expectation failed at \(file):\(line)") }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #fileID, line: UInt = #line) throws {
    // Never print compared values: tests should follow the same no-content-logging policy as the app.
    guard lhs == rhs else { throw CheckFailure("Equality failed at \(file):\(line)") }
}

func expectNil<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws {
    try expect(value == nil, file: file, line: line)
}

func require<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure("Missing value at \(file):\(line)") }
    return value
}

@main
struct Checks {
    @MainActor static func main() async {
        let tests = HistoryTests()
        defer { tests.cleanup() }
        let cases: [(String, () async throws -> Void)] = [
            ("exact deduplication and recency", tests.testExactDuplicateMovesToTopAndPreservesMetadata),
            ("byte-exact text and whitespace", tests.testByteExactDeduplicationAndWhitespace),
            ("category validation and deletion", tests.testCategoryValidationAndDeletionMovesRecordsToUncategorized),
            ("persistent content, category and settings", tests.testPersistenceAcrossIndependentConnections),
            ("Chinese/English/URL search and scope", tests.testSearchChineseEnglishURLAndLiteralPunctuationWithinFilter),
            ("capacity cleanup by recent copy", tests.testLimitEvictsOldestByLastCopyTime),
            ("version two migration removes favorite state without losing content", tests.testVersionTwoMigrationPreservesContentAndUnifiesCleanup),
            ("clear all history and preserve categories", tests.testClearRemovesAllHistoryAndPreservesCategories),
            ("pause and text size boundaries", tests.testPauseAndSizeBoundary),
            ("HTTP/HTTPS classification", tests.testLinkDetectionOnlyAcceptsCompleteHTTPURLs),
            ("pasteboard changes, self-copy and sensitive types", tests.testClipboardChangeCountPauseSensitiveTypesAndSelfCopy),
            ("actual polling timer", tests.testActualPollingTimerReceivesText),
            ("database failure feedback", tests.testFailedDatabaseOpenReportsError),
            ("transaction rollback and newer schema safety", tests.testFailedCapacityChangeRollsBackAndNewerSchemaIsPreserved),
            ("editing, metadata, reclassification and deduplication", tests.testEditingPreservesMetadataUpdatesTypeAndDeduplication),
            ("invalid and duplicate edits preserve original data", tests.testInvalidAndDuplicateEditsLeaveOriginalRecordsIntact),
            ("category colors and rename persistence", tests.testCategoryColorsPersistAndRenamingPreservesColor),
            ("version one migration preserves existing history", tests.testVersionOneMigrationPreservesExistingHistoryAndAssignsColors)
        ]
        var failures = 0
        for (name, test) in cases {
            do { try await test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(cases.count - failures)/\(cases.count) checks passed")
        if failures > 0 { exit(1) }
    }
}
