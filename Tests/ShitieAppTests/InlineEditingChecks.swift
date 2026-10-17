import AppKit

@main
struct InlineEditingChecks {
    struct Failure: Error {}
    static func check(_ value: Bool) throws { if !value { throw Failure() } }

    @MainActor static func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            guard Date() < deadline else { throw Failure() }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor static func main() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shitie-inline-\(UUID())")
        let pasteboard = NSPasteboard(name: .init("shitie-inline-\(UUID())"))
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            let url = directory.appendingPathComponent("history.sqlite")
            let repository = try HistoryRepository(url: url)
            let first = try await repository.capture("原文 Original")!
            let second = try await repository.capture("第二条 Second")!
            let model = AppModel(databaseURL: url, pasteboard: pasteboard)
            model.start()
            try await waitFor { model.isReady && model.clips.count == 2 }
            try check(model.selectedID == nil && model.detail == nil)
            model.selectedID = first
            try await waitFor { model.detail?.id == first }
            let original = model.detail!

            model.updateDraft(for: original, content: "修改后 Edited\n    indentation")
            model.selectedID = nil
            let extra = try await repository.capture("刷新不会重新展开")!
            model.refresh()
            try await waitFor { model.clips.count == 3 }
            try check(model.selectedID == nil && model.detail == nil)
            try check(model.drafts[first]?.content == "修改后 Edited\n    indentation")
            try await repository.delete(id: extra)
            model.refresh()
            try await waitFor { model.clips.count == 2 }
            print("PASS collapsed content stays closed after refresh and retains its draft")
            model.selectedID = second
            try await waitFor { model.detail?.id == second }
            model.search = "Second"
            try await waitFor { model.clips.count == 1 }
            model.revealDraft()
            try await waitFor { model.clips.count == 2 && model.detail?.id == first }
            try check(model.drafts[first]?.content == "修改后 Edited\n    indentation")
            model.discardDraft(id: first)
            try check(model.drafts.isEmpty)
            try check(try await repository.detail(id: first)?.content == original.content)
            print("PASS draft survives selection/search and cancel preserves original")

            model.updateDraft(for: original, content: " \n")
            model.saveDraft(id: first)
            try await waitFor { model.drafts[first]?.error != nil }
            try check(model.drafts[first]?.content == " \n" && model.drafts[first]?.isSaving == false)
            try check(try await repository.detail(id: first)?.content == original.content)
            model.issue = nil
            model.updateDraft(for: original, content: "已保存 Saved")
            model.saveDraft(id: first)
            try await waitFor { model.drafts.isEmpty && model.detail?.content == "已保存 Saved" }
            try check(try await repository.detail(id: first)?.content == "已保存 Saved")
            print("PASS failed save retains draft; successful save updates stored and displayed content")

            model.updateDraft(for: model.detail!, content: "复制修改 Copy edited")
            model.copy(id: first)
            try await waitFor { model.drafts.isEmpty && pasteboard.string(forType: .string) == "复制修改 Copy edited" }
            try check(try await repository.snapshot().totalCount == 2)
            print("PASS copy saves edited content and writes to isolated pasteboard without duplication")

            try await waitFor { model.detail?.content == "复制修改 Copy edited" }
            model.updateDraft(for: model.detail!, content: "保留未保存内容 Retained draft")
            try await repository.delete(id: first)
            model.refresh()
            try await waitFor { model.totalCount == 1 && model.clips.contains(where: { $0.id == first }) }
            model.selectedID = second
            model.revealDraft()
            try await waitFor { model.detail?.id == first }
            model.saveDraft(id: first)
            try await waitFor { model.drafts[first]?.error != nil }
            try check(model.drafts[first]?.content == "保留未保存内容 Retained draft")
            model.discardDraft(id: first)
            try await waitFor { !model.clips.contains(where: { $0.id == first }) }
            await model.prepareToQuit()
            print("PASS evicted record's draft remains reachable; discard removes it")
            print("5/5 inline editing checks passed")
        } catch {
            print("FAIL inline editing checks (no clipboard content logged)")
            exit(1)
        }
    }
}
