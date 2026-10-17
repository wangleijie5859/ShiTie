import Foundation

public enum ClipKind: String, Codable, Sendable {
    case text, link

    public static func detect(_ content: String) -> ClipKind {
        webURL(content) == nil ? .text : .link
    }

    public static func webURL(_ content: String) -> URL? {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { $0.isWhitespace }),
              let url = URL(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

public struct ClipSummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let preview: String
    public let kind: ClipKind
    public let createdAt: Date
    public let lastCopiedAt: Date
    public let categoryID: Int64?
    public let byteCount: Int
}

public struct ClipDetail: Identifiable, Equatable, Sendable {
    public let summary: ClipSummary
    public let content: String
    public var id: Int64 { summary.id }
}

public struct ClipCategory: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let color: CategoryColor
}

public enum CategoryColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case teal, blue, purple, pink, orange, green, red, gray
    public var id: Self { self }
    public static func suggested(excluding colors: [CategoryColor]) -> CategoryColor {
        let used = Set(colors)
        return allCases.first { !used.contains($0) } ?? allCases[colors.count % allCases.count]
    }
    public var title: String {
        switch self {
        case .teal: return "青色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .orange: return "橙色"
        case .green: return "绿色"
        case .red: return "红色"
        case .gray: return "灰色"
        }
    }
}

public enum ClipFilter: Hashable, Sendable {
    case all, uncategorized, category(Int64)
}

public struct HistorySettings: Equatable, Sendable {
    public var isPaused: Bool
    public var limit: Int
    public init(isPaused: Bool = false, limit: Int = 1_000) {
        self.isPaused = isPaused
        self.limit = limit
    }
}

public struct HistorySnapshot: Sendable {
    public let clips: [ClipSummary]
    public let categories: [ClipCategory]
    public let settings: HistorySettings
    public let totalCount: Int
}

public enum HistoryError: LocalizedError {
    case database(String)
    case invalidCategory(String)
    case tooLarge
    case invalidLimit
    case invalidText
    case emptyContent
    case duplicateContent
    case missingClip

    public var errorDescription: String? {
        switch self {
        case .database(let detail): return "本地数据库操作失败：\(detail)"
        case .invalidCategory(let detail): return detail
        case .tooLarge: return "这段内容超过 1 MiB，未保存。请分段复制；拾贴不会截断原文。"
        case .invalidLimit: return "历史记录上限需要在 1 至 100,000 之间。"
        case .invalidText: return "内容不是受支持的纯文本，未保存。"
        case .emptyContent: return "内容不能为空或只有空白字符。"
        case .duplicateContent: return "历史中已有完全相同的内容，请直接使用该记录。当前修改尚未保存。"
        case .missingClip: return "这条记录已被删除或清理，修改尚未保存。请先复制保留编辑框中的内容。"
        }
    }
}
