import AppKit
#if SWIFT_PACKAGE
import ShitieCore
#endif
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var categoryEditor: CategoryEditor?
    @State private var categoryToDelete: ClipCategory?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let issue = model.issue {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(issue).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if !model.isReady { Button("重试") { model.start() } }
                    Button { model.issue = nil } label: { ActionIcon("关闭提示", symbol: "xmark") }
                        .buttonStyle(.borderless)
                }.padding(12).background(Color.orange.opacity(0.1))
                Divider()
            }
            header
            Divider()
            if model.clips.isEmpty {
                Spacer()
                emptyList.padding(24)
                Spacer()
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.clips) { clip in
                        ClipRow(model: model, clip: clip, isSelected: model.selectedID == clip.id)
                            .tag(clip.id)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(model.selectedID == clip.id ? Color.primary.opacity(0.04) : Color.clear)
                                    .padding(.horizontal, 10)
                            )
                            .background(RecordRowInteraction(isExpanded: model.selectedID == clip.id) {
                                if model.selectedID == clip.id { model.selectedID = nil }
                            }.allowsHitTesting(false))
                    }
                }.listStyle(.inset).accessibilityLabel("剪贴板历史记录")
            }
            Divider()
            HStack {
                if !model.drafts.isEmpty {
                    Button("\(model.drafts.count) 条修改未保存") { model.revealDraft() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.orange)
                        .help("返回未保存的修改")
                } else {
                    Text(model.search.isEmpty ? "内容仅保存在这台 Mac" : "在“\(model.filterTitle)”中搜索")
                        .font(.caption).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let feedback = model.feedback {
                    Text(feedback).font(.caption).foregroundStyle(.teal)
                }
            }.foregroundStyle(.secondary).padding(12)
        }
        .frame(minWidth: 560, minHeight: 500)
        .accentColor(.teal)
        .sheet(item: $categoryEditor) { editor in
            CategorySheet(model: model, category: editor.category)
        }
        .alert("删除分类？", isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } })) {
            Button("取消", role: .cancel) { categoryToDelete = nil }
            Button("删除分类", role: .destructive) {
                if let category = categoryToDelete { model.deleteCategory(category) }
                categoryToDelete = nil
            }
        } message: {
            Text("“\(categoryToDelete?.name ?? "")”内的记录会移入“未分类”，内容会保留。")
        }
        .onChange(of: model.focusSearchRequest) { _ in
            model.selectedID = nil
            searchFocused = true
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("拾贴").font(.headline)
                Text("\(model.clips.count) 条").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(model.settings.isPaused ? Color.orange : Color.teal).frame(width: 5, height: 5)
                    Text(!model.isReady ? "载入中" : (model.settings.isPaused ? "已暂停" : "记录中"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { categoryEditor = CategoryEditor(category: nil) } label: {
                    ActionIcon("新建分类", symbol: "plus")
                }.disabled(!model.isReady).help("新建分类")
                Menu {
                    ForEach(model.categories) { category in
                        Menu(category.name) {
                            Button("编辑名称与颜色…") { categoryEditor = CategoryEditor(category: category) }
                            Button("删除分类…", role: .destructive) { categoryToDelete = category }
                        }
                    }
                } label: { ActionIcon("管理分类", symbol: "slider.horizontal.3") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .disabled(model.categories.isEmpty).help("管理分类名称与颜色")
                Button { model.togglePause() } label: {
                    ActionIcon(model.settings.isPaused ? "恢复记录" : "暂停记录", symbol: model.settings.isPaused ? "play.circle" : "pause.circle")
                }.disabled(!model.isReady || model.isChangingPause)
                    .help(model.settings.isPaused ? "恢复记录" : "暂停记录")
                Button { model.openSettings?() } label: { ActionIcon("设置", symbol: "gearshape") }
                    .help("设置（⌘,）")
            }.buttonStyle(.borderless)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 7) {
                        filterButton("全部", filter: .all)
                        filterButton("未分类", filter: .uncategorized)
                        ForEach(model.categories) { category in
                            filterButton(category.name, filter: .category(category.id), color: category.color.tint)
                                .contextMenu {
                                    Button("编辑分类与颜色…") { categoryEditor = CategoryEditor(category: category) }
                                    Button("删除分类…", role: .destructive) { categoryToDelete = category }
                                }
                        }
                    }
                }.frame(height: 34)
                    .onChange(of: model.filter) { proxy.scrollTo($0, anchor: .center) }
                    .onChange(of: model.categories) { _ in proxy.scrollTo(model.filter, anchor: .center) }
                    .onAppear { proxy.scrollTo(model.filter, anchor: .center) }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索当前分类", text: $model.search).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityLabel("搜索当前分类的内容")
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
                }
            }.padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }.padding(14)
    }

    private func filterButton(_ title: String, filter: ClipFilter, color: Color? = nil) -> some View {
        let selected = model.filter == filter
        return Button { model.filter = filter } label: {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(title).lineLimit(1)
            }.font(.callout).padding(.horizontal, 11).padding(.vertical, 5)
                .background(Color.primary.opacity(selected ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(selected ? 0.14 : 0.08), lineWidth: 1))
        }.buttonStyle(.plain).id(filter)
            .accessibilityLabel(title).accessibilityValue(selected ? "已选择" : "未选择")
    }

    @ViewBuilder private var emptyList: some View {
        if !model.isReady {
            EmptyState(icon: "tray", title: "准备历史记录", message: "正在打开本机数据库。若载入失败，请按上方提示重试。")
        } else if !model.search.isEmpty {
            EmptyState(icon: "magnifyingglass", title: "没有匹配的内容", message: "试试其他关键词，或切换到“全部”搜索。")
        } else if model.filter != .all {
            EmptyState(icon: "folder", title: "这个分类还是空的", message: "点击记录的文件夹图标，即可更改所属分类。")
        } else {
            EmptyState(icon: "doc.on.clipboard", title: "从一次复制开始", message: model.settings.isPaused ? "点击顶部的恢复图标后，复制文字或网页链接。" : "复制文字或网页链接，拾贴会自动保存在这里。启动前的剪贴板不会被读取。")
        }
    }
}

private struct ClipRow: View {
    @ObservedObject var model: AppModel
    let clip: ClipSummary
    let isSelected: Bool
    @State private var showingInfo = false

    private var category: ClipCategory? { model.categories.first { $0.id == clip.categoryID } }
    private var detail: ClipDetail? { model.detail.flatMap { $0.id == clip.id ? $0 : nil } }
    private var draft: AppModel.Draft? { model.drafts[clip.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: isSelected ? 6 : 10) {
            if isSelected, let detail {
                PlainTextView(text: draft?.content ?? detail.content, isEditable: draft?.isSaving != true,
                              onChange: { model.updateDraft(for: detail, content: $0) })
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                if let error = draft?.error {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(draft.map { String($0.content.prefix(240)) } ?? clip.preview).font(.system(size: 13)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if draft != nil { Text("修改未保存").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                if let category {
                    CategoryBadge(category: category).layoutPriority(-1)
                } else {
                    Text("未分类").font(.caption2).foregroundStyle(.secondary)
                }
                Text(clip.lastCopiedAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                if isSelected {
                    Text(draft == nil ? "可直接编辑" : (draft?.isSaving == true ? "保存中…" : "未保存 · ⌘S"))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).layoutPriority(-2)
                }
                Spacer(minLength: 4)
                actions
            }
            if isSelected, clip.byteCount > 100_000 {
                Text("较长内容已完整保留，可在上方滚动查看。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, isSelected ? 8 : 10)
            .foregroundStyle(Color(nsColor: .labelColor))
            .accessibilityElement(children: .contain)
            .accessibilityHint(isSelected ? "点击记录外区域收起完整内容" : "点击记录查看和编辑完整内容")
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if draft != nil {
                if isSelected {
                    saveButton.keyboardShortcut("s", modifiers: .command)
                } else { saveButton }
                Button { model.discardDraft(id: clip.id) } label: { ActionIcon("取消修改", symbol: "arrow.uturn.backward") }
                    .help("取消修改，恢复已保存的内容")
            }
            if isSelected {
                copyButton.keyboardShortcut("c", modifiers: [.command, .shift])
            } else { copyButton }
            Menu {
                Button("未分类") { model.move(id: clip.id, to: nil) }
                ForEach(model.categories) { category in
                    Button(category.name) { model.move(id: clip.id, to: category.id) }
                }
            } label: { ActionIcon("修改所属分类", symbol: "folder") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("修改所属分类")
            if clip.kind == .link {
                Button { model.openLink(id: clip.id) } label: { ActionIcon("在浏览器打开", symbol: "arrow.up.right.square") }
                    .disabled(draft != nil).help(draft == nil ? "在浏览器打开" : "保存修改后打开链接")
            }
            Button { showingInfo = true } label: { ActionIcon("查看记录信息", symbol: "info.circle") }
                .help("查看记录信息").popover(isPresented: $showingInfo) { metadata }
            if isSelected {
                deleteButton.keyboardShortcut(.delete, modifiers: [.command, .shift])
            } else { deleteButton }
        }.buttonStyle(.borderless).controlSize(.small).disabled(draft?.isSaving == true)
    }

    private var copyButton: some View {
        Button { model.copy(id: clip.id) } label: { ActionIcon(draft == nil ? "复制完整内容" : "保存修改并复制", symbol: "doc.on.doc") }
            .help(draft == nil ? "复制完整内容" : "保存修改并复制")
    }

    private var saveButton: some View {
        Button { model.saveDraft(id: clip.id) } label: { ActionIcon("保存修改", symbol: "checkmark") }
            .help("保存修改（⌘S）")
    }

    private var deleteButton: some View {
        Button(role: .destructive) { model.delete(id: clip.id) } label: { ActionIcon("删除记录", symbol: "trash") }
            .help("删除记录（⇧⌘⌫）")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(clip.kind == .link ? "网页链接" : "文字").font(.headline)
            LabeledContent("首次记录", value: clip.createdAt.formatted(date: .numeric, time: .standard))
            LabeledContent("最近复制", value: clip.lastCopiedAt.formatted(date: .numeric, time: .standard))
            LabeledContent("内容大小", value: ByteCountFormatter.string(fromByteCount: Int64(clip.byteCount), countStyle: .file))
        }.font(.caption).padding(18).frame(width: 300)
    }
}

/// Preserve native selection and text input; observe outside clicks without consuming them.
private struct RecordRowInteraction: NSViewRepresentable {
    let isExpanded: Bool
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> SelectionView { SelectionView(frame: .zero) }
    func updateNSView(_ view: SelectionView, context: Context) {
        view.onClickOutside = isExpanded ? onClickOutside : nil
        view.updateMonitor()
        view.removeAccentHighlight()
    }

    final class SelectionView: NSView {
        var onClickOutside: (() -> Void)?
        private var monitor: Any?
        private var clickStartedOutside = false
        private weak var tableView: NSTableView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
            removeAccentHighlight()
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        func updateMonitor() {
            guard window != nil, onClickOutside != nil else {
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
                return
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let outside = !self.visibleRect.contains(self.convert(event.locationInWindow, from: nil))
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    self.clickStartedOutside = outside
                    // Header/footer controls stay fixed and may consume mouse-up while tracking.
                    if outside, let table = self.tableView,
                       !table.visibleRect.contains(table.convert(event.locationInWindow, from: nil)),
                       let collapse = self.onClickOutside {
                        DispatchQueue.main.async(execute: collapse)
                    }
                    return event
                }
                // A text-selection drag that starts inside the record must keep it open.
                guard self.clickStartedOutside, outside,
                      let collapse = self.onClickOutside else { return event }
                self.clickStartedOutside = false
                // Wait until mouse-up is delivered so collapsing cannot move the click target.
                DispatchQueue.main.async(execute: collapse)
                return event
            }
        }

        func removeAccentHighlight() {
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? NSTableView {
                    tableView = table
                    table.selectionHighlightStyle = .none
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

private struct ActionIcon: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    var body: some View {
        Label(title, systemImage: symbol).labelStyle(.iconOnly)
            .frame(width: 24, height: 24).contentShape(Rectangle())
            .accessibilityLabel(title)
    }
}

private struct PlainTextView: NSViewRepresentable {
    let text: String
    var isEditable = true
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            onChange(view.string)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NSTextView()
        view.isEditable = isEditable
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textColor = .labelColor
        view.selectedTextAttributes = [.backgroundColor: NSColor.unemphasizedSelectedTextBackgroundColor, .foregroundColor: NSColor.textColor]
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.layoutManager?.allowsNonContiguousLayout = true
        view.setAccessibilityLabel("完整内容，可直接编辑")
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = isEditable
        guard !view.string.utf8.elementsEqual(text.utf8) else { return }
        view.string = text
        view.undoManager?.removeAllActions()
        view.scrollToBeginningOfDocument(nil)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let view = scroll.documentView as? NSTextView,
              let container = view.textContainer, let layout = view.layoutManager else { return nil }
        // Measure only short text; long documents keep a bounded, scrollable viewport.
        guard text.utf8.count <= 4096 else { return CGSize(width: width, height: 180) }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let extraLine = layout.extraLineFragmentTextContainer === container ? layout.extraLineFragmentRect.maxY : 0
        let contentHeight = max(layout.usedRect(for: container).maxY, extraLine) + view.textContainerInset.height * 2
        return CGSize(width: width, height: min(180, max(32, ceil(contentHeight))))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: 290)
    }
}

private struct CategoryEditor: Identifiable {
    let id = UUID()
    let category: ClipCategory?
}

private struct CategorySheet: View {
    @ObservedObject var model: AppModel
    let category: ClipCategory?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: CategoryColor = .teal
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(category == nil ? "新建分类" : "编辑分类").font(.headline)
            TextField("分类名称", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { save() }.accessibilityLabel("分类名称，最多40个字符")
            VStack(alignment: .leading, spacing: 8) {
                Text("分类颜色 · \(color.title)").font(.callout)
                HStack(spacing: 4) {
                    ForEach(CategoryColor.allCases) { option in
                        Button { color = option } label: {
                            Circle().fill(option.tint).frame(width: 20, height: 20)
                                .overlay {
                                    if color == option { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                                }
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 6).stroke(color == option ? option.tint : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityLabel(option.title)
                            .accessibilityValue(color == option ? "已选择" : "未选择").help(option.title)
                    }
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(saving)
            }
        }.padding(24).frame(width: 350)
            .onAppear {
                name = category?.name ?? ""
                color = category?.color ?? CategoryColor.suggested(excluding: model.categories.map(\.color))
                focused = true
            }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        model.saveCategory(name: name, id: category?.id, color: color) { message in
            saving = false
            if let message { error = message } else { dismiss() }
        }
    }
}

private struct CategoryBadge: View {
    let category: ClipCategory
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(category.color.tint).frame(width: 6, height: 6)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 0.5))
            Text(category.name).lineLimit(1)
        }.font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(category.color.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(category.color.tint.opacity(0.35), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(category.name)，\(category.color.title)")
    }
}

private extension CategoryColor {
    var tint: Color {
        switch self {
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .red: return .red
        case .gray: return .gray
        }
    }
}
