import AppKit
import Combine
#if SWIFT_PACKAGE
import ShitieCore
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var clips: [ClipSummary] = []
    @Published private(set) var categories: [ClipCategory] = []
    @Published private(set) var settings = HistorySettings()
    @Published private(set) var totalCount = 0
    @Published private(set) var isReady = false
    @Published private(set) var isChangingPause = false
    @Published private(set) var detail: ClipDetail?
    struct Draft {
        let original: ClipDetail
        var content: String
        var error: String?
        var isSaving = false
    }
    @Published private(set) var drafts: [Int64: Draft] = [:]
    @Published var issue: String?
    @Published var feedback: String?
    @Published var focusSearchRequest = 0
    @Published var filter: ClipFilter = .all { didSet { if oldValue != filter { selectedID = nil; refresh() } } }
    @Published var search = "" { didSet { if oldValue != search { selectedID = nil; refresh() } } }
    @Published var selectedID: Int64? { didSet { if oldValue != selectedID { loadDetail() } } }

    var openSettings: (() -> Void)?
    private var repository: HistoryRepository?
    private var isStarting = false
    private var isStopping = false
    private var pendingOperations = 0
    private var refreshGeneration = 0
    private var detailGeneration = 0
    private var feedbackTask: Task<Void, Never>?
    private let databaseURL: URL
    private let pasteboard: NSPasteboard
    private lazy var monitor = PasteboardMonitor(pasteboard: pasteboard) { [weak self] event in self?.receive(event) }

    init(databaseURL: URL = HistoryRepository.defaultURL, pasteboard: NSPasteboard = .general) {
        self.databaseURL = databaseURL
        self.pasteboard = pasteboard
    }

    var filterTitle: String {
        switch filter {
        case .all: return "全部"
        case .uncategorized: return "未分类"
        case .category(let id): return categoryName(id) ?? "未分类"
        }
    }

    func categoryName(_ id: Int64?) -> String? { categories.first { $0.id == id }?.name }

    func start() {
        guard repository == nil, !isStarting else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                let url = databaseURL
                let repository = try await Task.detached(priority: .userInitiated) {
                    try HistoryRepository(url: url)
                }.value
                let loadedSettings = try await repository.settings()
                self.repository = repository
                settings = loadedSettings
                if !isStopping { monitor.start(paused: settings.isPaused) }
                isReady = true
                issue = nil
                refresh()
            } catch {
                issue = "无法载入历史记录，自动记录尚未开始。\(error.localizedDescription) 请检查磁盘空间和数据目录权限，然后重试。"
            }
        }
    }

    func prepareToQuit() async {
        isStopping = true
        monitor.stop()
        // Let already accepted mutations finish before AppKit terminates the process.
        while pendingOperations > 0 || isStarting {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func receive(_ event: ClipboardEvent) {
        switch event {
        case .text(let content):
            perform { try await $0.capture(content) }
        case .oversized: issue = HistoryError.tooLarge.localizedDescription
        case .unsupportedText: issue = HistoryError.invalidText.localizedDescription
        }
    }

    func refresh() {
        guard let repository else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let filter = filter
        let search = search
        Task {
            do {
                let snapshot = try await repository.snapshot(filter: filter, search: search)
                guard generation == refreshGeneration else { return }
                let oldIndex = clips.firstIndex { $0.id == selectedID } ?? 0
                clips = snapshot.clips
                // Keep an evicted record's unsaved text reachable until saved or discarded.
                if filter == .all && search.isEmpty {
                    let visibleIDs = Set(clips.map(\.id))
                    clips += drafts.values.filter { !visibleIDs.contains($0.original.id) }
                        .map { $0.original.summary }.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
                }
                categories = snapshot.categories
                settings = snapshot.settings
                totalCount = snapshot.totalCount
                if let selectedID, !clips.contains(where: { $0.id == selectedID }) {
                    self.selectedID = clips.isEmpty ? nil : clips[min(oldIndex, clips.count - 1)].id
                } else {
                    loadDetail()
                }
            } catch { issue = error.localizedDescription }
        }
    }

    private func loadDetail() {
        detailGeneration += 1
        let generation = detailGeneration
        if detail?.id != selectedID { detail = nil }
        guard let repository, let selectedID else { return }
        Task {
            do {
                let result = try await repository.detail(id: selectedID)
                guard generation == detailGeneration else { return }
                detail = result ?? drafts[selectedID]?.original
            } catch { issue = error.localizedDescription }
        }
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable (HistoryRepository) async throws -> T) {
        guard let repository, !isStopping else { return }
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                _ = try await operation(repository)
                refresh()
            } catch { issue = "操作未保存。\(error.localizedDescription)" }
        }
    }

    func togglePause() {
        guard let repository, !isChangingPause, !isStopping else { return }
        pendingOperations += 1
        isChangingPause = true
        let previous = settings.isPaused
        let paused = !previous
        // Stop reading immediately; persisting the preference must not delay pausing.
        monitor.setPaused(true)
        Task {
            defer { isChangingPause = false; pendingOperations -= 1 }
            do {
                try await repository.setPaused(paused)
                settings.isPaused = paused
                monitor.setPaused(paused)
            } catch {
                monitor.setPaused(previous)
                issue = "记录状态未更改。\(error.localizedDescription)"
            }
        }
    }

    func copy(id: Int64) {
        if drafts[id] != nil { saveDraft(id: id, copyAfterSaving: true); return }
        guard let repository, !isStopping else { return }
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                guard let detail = try await repository.detail(id: id) else { return }
                guard monitor.copy(detail.content) else {
                    issue = "无法写入系统剪贴板，请重试。"; return
                }
                showFeedback("已复制")
                try await repository.markCopied(id: id)
                refresh()
            } catch { issue = "操作未保存。\(error.localizedDescription)" }
        }
    }

    func move(id: Int64, to categoryID: Int64?) {
        perform { try await $0.move(id: id, to: categoryID) }
    }

    func delete(id: Int64) {
        guard let repository, !isStopping, drafts[id]?.isSaving != true else { return }
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                try await repository.delete(id: id)
                drafts[id] = nil
                refresh()
            } catch { issue = "操作未保存。\(error.localizedDescription)" }
        }
    }

    func updateDraft(for clip: ClipDetail, content: String) {
        guard !isStopping, drafts[clip.id]?.isSaving != true else { return }
        let original = drafts[clip.id]?.original ?? clip
        if content.utf8.elementsEqual(original.content.utf8) {
            drafts[clip.id] = nil
        } else {
            drafts[clip.id] = Draft(original: original, content: content)
        }
    }

    func discardDraft(id: Int64) {
        guard drafts[id]?.isSaving != true else { return }
        drafts[id] = nil
        refresh()
    }

    func revealDraft() {
        guard let id = drafts.keys.sorted().first else { return }
        filter = .all
        search = ""
        selectedID = id
        refresh()
    }

    func openLink(id: Int64) {
        guard let repository, !isStopping else { return }
        Task {
            do {
                guard let clip = try await repository.detail(id: id), let url = ClipKind.webURL(clip.content) else {
                    issue = "这条记录已不存在，或不再是网页链接。"; return
                }
                if !NSWorkspace.shared.open(url) { issue = "无法在浏览器中打开这个链接。" }
            } catch { issue = error.localizedDescription }
        }
    }

    func saveDraft(id: Int64, copyAfterSaving: Bool = false) {
        guard let repository, !isStopping, let draft = drafts[id], !draft.isSaving else { return }
        drafts[id]?.isSaving = true
        drafts[id]?.error = nil
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                try await repository.edit(id: id, content: draft.content)
                // Refresh the selected original before removing its draft, avoiding a flash of old text.
                let saved = try await repository.detail(id: id)
                if selectedID == id { detailGeneration += 1; detail = saved }
                drafts[id] = nil
                refresh()
                if copyAfterSaving { copy(id: id) } else { showFeedback("已保存") }
            } catch {
                drafts[id]?.isSaving = false
                drafts[id]?.error = error.localizedDescription
                issue = "修改尚未保存。\(error.localizedDescription)"
            }
        }
    }

    func saveCategory(name: String, id: Int64?, color: CategoryColor, completion: @escaping (String?) -> Void) {
        guard let repository, !isStopping else { completion("数据尚未载入。"); return }
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                let savedID = try await repository.saveCategory(name: name, id: id, color: color)
                if id == nil { filter = .category(savedID); search = "" }
                refresh()
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }

    func deleteCategory(_ category: ClipCategory) {
        guard let repository, !isStopping else { return }
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                try await repository.deleteCategory(id: category.id)
                if filter == .category(category.id) { filter = .uncategorized }
                refresh()
            } catch { issue = error.localizedDescription }
        }
    }

    func setLimit(_ limit: Int) { perform { try await $0.setLimit(limit) } }
    func clearHistory() {
        guard let repository, !isStopping, !drafts.values.contains(where: \.isSaving) else { return }
        pendingOperations += 1
        Task {
            defer { pendingOperations -= 1 }
            do {
                try await repository.clear()
                drafts.removeAll()
                refresh()
            } catch { issue = "操作未保存。\(error.localizedDescription)" }
        }
    }

    private func showFeedback(_ text: String) {
        feedbackTask?.cancel()
        feedback = text
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { feedback = nil }
        }
    }
}
