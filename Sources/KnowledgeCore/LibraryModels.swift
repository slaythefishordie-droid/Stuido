import Foundation

public enum CardKind: String, Codable, CaseIterable, Sendable { case word, expression, keyword, key_sentence }
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case pdf, epub, youtube, local_video, text, article, podcast
}
public enum Organization: String, Codable, CaseIterable, Sendable { case inbox, saved, archived }
public enum ReviewStatus: String, Codable, CaseIterable, Sendable { case not_enrolled, active, paused }
public enum Discovery: String, Codable, Sendable { case `self`, ai, both }

public struct ReadingLocator: Codable, Equatable, Sendable {
    public var kind: String
    public var page: Int?
    public var seconds: Double?
    public var href: String?
    public var progression: Double?
    public var nativeJSON: String?
    public var fileFingerprint: String?
    public var anchorText: String?
    public var pdfTextAnchors: [PDFTextAnchor]?
    public var pdfTextQuads: [PDFTextQuad]?
    public var rectangles: [HighlightRect] = []
    public init(
        kind: String, page: Int? = nil, seconds: Double? = nil, href: String? = nil,
        progression: Double? = nil, nativeJSON: String? = nil
    ) {
        self.kind = kind
        self.page = page
        self.seconds = seconds
        self.href = href
        self.progression = progression
        self.nativeJSON = nativeJSON
    }
    public func validate() throws {
        if let page, page < 1 { throw LibraryError.invalid("PDF 页序必须从 1 开始") }
        if let seconds, !seconds.isFinite || seconds < 0 || seconds > 3_155_760_000 {
            throw LibraryError.invalid("时间定位无效")
        }
        if let progression, !progression.isFinite || !(0...1).contains(progression) {
            throw LibraryError.invalid("阅读进度无效")
        }
        guard ["pdf", "epub", "video", "article", "podcast"].contains(kind) else {
            throw LibraryError.invalid("未知定位类型")
        }
    }
}
public struct HighlightRect: Codable, Equatable, Sendable {
    public var page: Int
    public var x: Double, y: Double, width: Double, height: Double
    public init(page: Int, x: Double, y: Double, width: Double, height: Double) {
        self.page = page
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
public struct LibrarySource: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var kind: SourceKind
    public var title: String
    public var url: String?
    public var assetHash: String?
    public var assetExtension: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var lastLocation: ReadingLocator?
    public var lastReadAt: Date?
    public var deletedAt: Date?
    public init(
        id: UUID = UUID(), kind: SourceKind, title: String, url: String? = nil, assetHash: String? = nil,
        assetExtension: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.assetHash = assetHash
        self.assetExtension = assetExtension
    }
}
public struct LibraryMark: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var sourceID: UUID
    public var locator: ReadingLocator
    public var excerpt: String
    public var note: String = ""
    public var createdAt: Date = Date()
    public var externalUpdatedAt: Double?
    public var cardKind: CardKind?
    public var organization: Organization = .inbox
    public var deletedAt: Date?
    public init(
        id: UUID = UUID(), sourceID: UUID, locator: ReadingLocator, excerpt: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.locator = locator
        self.excerpt = excerpt
        self.createdAt = createdAt
    }
}
public struct CardReference: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var sourceID: UUID
    public var locator: ReadingLocator?
    public init(id: UUID = UUID(), sourceID: UUID, locator: ReadingLocator? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.locator = locator
    }
}
public struct FieldOrigin: Codable, Equatable, Sendable {
    public var kind: String
    public var sourceRefIDs: [UUID]
    public init(kind: String, sourceRefIDs: [UUID] = []) {
        self.kind = kind
        self.sourceRefIDs = sourceRefIDs
    }
}
public struct LibraryCard: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var type: CardKind
    public var content: [String: String]
    public var language = "en"
    public var tags: [String] = []
    public var sourceRefs: [CardReference] = []
    public var markIDs: [UUID] = []
    public var provenance: [String: FieldOrigin] = [:]
    public var note = ""
    public var importAnnotation = ""
    public var discovery: Discovery = .self
    public var organization: Organization = .saved
    public var review: ReviewStatus = .not_enrolled
    public var schedule: ReviewSchedule?
    public var createdAt = Date()
    public var updatedAt = Date()
    public var deletedAt: Date?
    public init(type: CardKind, content: [String: String]) {
        self.type = type
        self.content = content
    }
    public var title: String { content["word"] ?? content["term"] ?? content["text"] ?? "" }
    public static func fields(for type: CardKind) -> [String] {
        switch type {
        case .word: ["word", "definition_en", "example_en"]
        case .expression: ["text"]
        case .keyword: ["term", "explanation"]
        case .key_sentence: ["text", "explanation"]
        }
    }
}
public struct LibraryProject: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var note = ""
    public var sourceIDs: [UUID] = []
    public var cardIDs: [UUID] = []
    public var relationIDs: [UUID] = []
    public var board: ProjectBoard?
    public var groups: [ProjectGroup]?
    public var sourceNotes: [String: String]?
    public var deletedAt: Date?
    public init(title: String) { self.title = title }
}
public struct LibraryRelation: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var from: UUID
    public var to: UUID
    public var kind: String
    public var note = ""
    public var deletedAt: Date?
    public init(from: UUID, to: UUID, kind: String) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}
public struct PendingImport: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var packageID: String
    public var title: String
    public var json: String
    public var createdAt = Date()
    public init(packageID: String, title: String, json: String) {
        self.packageID = packageID
        self.title = title
        self.json = json
    }
}
public struct LibraryState: Codable, Equatable, Sendable {
    public var version = 1
    public var sources: [LibrarySource] = []
    public var marks: [LibraryMark] = []
    public var cards: [LibraryCard] = []
    public var projects: [LibraryProject] = []
    public var relations: [LibraryRelation] = []
    public var pending: [PendingImport] = []
    public var importedPackages: [String: String] = [:]
    public var migrations: [String] = []
    public var receivedWebIDs: [UUID] = []
    public var reviewRecords: [LibraryReviewRecord] = []
    public init() {}

    public func validate() throws {
        guard version == 1 else { throw LibraryError.invalid("不支持的知识库版本，原数据已保留") }
        func unique(_ ids: [UUID]) throws {
            guard Set(ids).count == ids.count else { throw LibraryError.invalid("重复对象编号") }
        }
        try unique(
            sources.map(\.id) + marks.map(\.id) + cards.map(\.id) + projects.map(\.id) + relations.map(\.id)
                + pending.map(\.id) + reviewRecords.map(\.id))
        let sourceIDs = Set(sources.map(\.id))
        let cardIDs = Set(cards.map(\.id))
        let markIDs = Set(marks.map(\.id))
        let relationIDs = Set(relations.map(\.id))
        let sourceKinds = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.kind) })
        for source in sources {
            guard !source.title.isEmpty else { throw LibraryError.invalid("资料名称不能为空") }
            if let hash = source.assetHash {
                guard hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                    throw LibraryError.invalid("资料摘要无效")
                }
            }
            if let ext = source.assetExtension {
                guard ["pdf", "epub", "mp4", "mov", "m4v"].contains(ext) else {
                    throw LibraryError.invalid("资料文件类型无效")
                }
            }
            if let value = source.url {
                guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil,
                    url.password == nil
                else { throw LibraryError.invalid("资料链接无效") }
            }
            try source.lastLocation?.validate()
            if let locator = source.lastLocation { try validateLocatorKind(locator, source: source.kind) }
        }
        for mark in marks {
            guard sourceIDs.contains(mark.sourceID) else { throw LibraryError.invalid("Mark 资料引用缺失") }
            try mark.locator.validate()
            try validateLocatorKind(mark.locator, source: sourceKinds[mark.sourceID]!)
        }
        for card in cards {
            try card.schedule?.validate()
            let allowed = LibraryCard.fields(for: card.type)
            let required = card.type == .word ? allowed : [allowed[0]]
            guard
                required.allSatisfy({
                    !(card.content[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                }), Set(card.content.keys).isSubset(of: Set(allowed))
            else { throw LibraryError.invalid("卡片必填内容或类型无效") }
            guard Set(card.markIDs).isSubset(of: markIDs) else { throw LibraryError.invalid("卡片 Mark 引用缺失") }
            try unique(card.sourceRefs.map(\.id))
            for ref in card.sourceRefs {
                guard sourceIDs.contains(ref.sourceID) else { throw LibraryError.invalid("卡片资料引用缺失") }
                try ref.locator?.validate()
                if let locator = ref.locator {
                    try validateLocatorKind(locator, source: sourceKinds[ref.sourceID]!)
                }
            }
            for origin in card.provenance.values {
                guard ["original", "ai_explanation", "ai_generated", "user_input"].contains(origin.kind),
                    Set(origin.sourceRefIDs).isSubset(of: Set(card.sourceRefs.map(\.id))),
                    origin.kind != "original" || !origin.sourceRefIDs.isEmpty
                else { throw LibraryError.invalid("字段出处无效") }
            }
        }
        for record in reviewRecords {
            guard cardIDs.contains(record.cardID), (1...4).contains(record.rating),
                record.elapsedMilliseconds >= 0
            else { throw LibraryError.invalid("复习记录无效") }
        }
        for relation in relations {
            guard cardIDs.contains(relation.from), cardIDs.contains(relation.to), relation.from != relation.to
            else { throw LibraryError.invalid("关系端点缺失或自引用") }
        }
        for project in projects {
            try project.board?.validate(sourceIDs: sourceIDs, cardIDs: cardIDs)
            let groups = project.groups ?? []
            try unique(groups.map(\.id))
            for group in groups {
                guard !group.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    Set(group.sourceIDs).isSubset(of: sourceIDs), Set(group.cardIDs).isSubset(of: cardIDs)
                else { throw LibraryError.invalid("项目分组名称或引用无效") }
            }
            for key in (project.sourceNotes ?? [:]).keys {
                guard let id = UUID(uuidString: key), sourceIDs.contains(id) else {
                    throw LibraryError.invalid("项目笔记引用的资料不存在")
                }
            }
            guard Set(project.sourceIDs).isSubset(of: sourceIDs), Set(project.cardIDs).isSubset(of: cardIDs),
                Set(project.relationIDs).isSubset(of: relationIDs)
            else { throw LibraryError.invalid("项目关联对象缺失") }
        }
    }
}
private func validateLocatorKind(_ locator: ReadingLocator, source: SourceKind) throws {
    let expected = [.youtube, .local_video].contains(source) ? "video" : source.rawValue
    guard locator.kind == expected else { throw LibraryError.invalid("定位类型与资料不一致") }
}

public enum LibraryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

public struct LibraryReviewRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var cardID: UUID
    public var rating: Int
    public var reviewedAt: Date
    public var elapsedMilliseconds: Int
    public var deletedAt: Date?
    public var schedulerVersion: String
    public var schedulerBefore: Data?
    public var schedulerAfter: Data?
    public var schedulerLog: Data?
    public var schedulerParameters: Data?
    public init(
        cardID: UUID, rating: Int, reviewedAt: Date, elapsedMilliseconds: Int, schedulerVersion: String
    ) {
        self.cardID = cardID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.elapsedMilliseconds = elapsedMilliseconds
        self.schedulerVersion = schedulerVersion
    }
}
