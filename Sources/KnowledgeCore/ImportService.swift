import Foundation
import JSONSchema

public struct ImportPreview: Sendable {
    public let packageID: String
    public let title: String
    public let sources: [LibrarySource]
    public let cards: [LibraryCard]
    public let relations: [LibraryRelation]
    public let canonical: String
    public let duplicateCardIDs: Set<UUID>
    public let warnings: [String]
}

public enum ImportService {
    public static func preview(_ text: String, existing: LibraryState, sourceMatches: [String: UUID] = [:])
        throws -> ImportPreview
    {
        let data = Data(text.utf8)
        guard data.count <= 10 * 1024 * 1024 else { throw LibraryError.invalid("JSON 超过 10 MiB") }
        try StrictJSON.check(data)
        guard
            let schemaURL = Bundle.module.url(
                forResource: "import-package-1.0.schema", withExtension: "json", subdirectory: "Resources")
        else { throw LibraryError.invalid("导入协议资源缺失") }
        let schema = try Schema(instance: String(contentsOf: schemaURL, encoding: .utf8))
        let validation = try schema.validate(instance: text)
        guard validation.isValid else {
            throw LibraryError.invalid(
                try validation.renderedOutput(level: .basic).serialized(options: .pretty))
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibraryError.invalid("JSON 顶层必须是对象")
        }
        let packageID = root["package_id"] as! String
        let canonical = try encode(root)
        if let previous = existing.importedPackages[packageID] {
            throw LibraryError.invalid(previous == canonical ? "此批次已经导入" : "同一批次编号的内容已改变，请核对后使用新的批次编号")
        }
        if existing.importedPackages.values.contains(canonical) { throw LibraryError.invalid("相同内容已导入") }
        var sourceMap: [String: UUID] = [:]
        var cardMap: [String: UUID] = [:]
        var sources: [LibrarySource] = []
        var cards: [LibraryCard] = []
        var relations: [LibraryRelation] = []
        var warnings: [String] = []
        func unique(_ keys: [String]) throws {
            guard Set(keys).count == keys.count else { throw LibraryError.invalid("包内编号重复") }
        }
        let rawSources = root["sources"] as! [[String: Any]]
        let rawCards = root["cards"] as! [[String: Any]]
        let rawRelations = root["relations"] as! [[String: Any]]
        try unique(rawSources.map { $0["id"] as! String })
        try unique(rawCards.map { $0["id"] as! String })
        try unique(rawRelations.map { $0["id"] as! String })
        for raw in rawSources {
            let key = raw["id"] as! String
            let kind = SourceKind(rawValue: raw["kind"] as! String)!
            let url = raw["url"] as? String
            let hash = raw["sha256"] as? String
            let match =
                sourceMatches[key].flatMap { id in
                    existing.sources.first { $0.id == id && $0.deletedAt == nil && $0.kind == kind }
                }
                ?? existing.sources.first {
                    $0.deletedAt == nil && $0.kind == kind
                        && ((hash != nil && $0.assetHash == hash) || (url != nil && $0.url == url))
                }
            if let requested = sourceMatches[key], match?.id != requested {
                throw LibraryError.invalid("资料匹配无效或类型不符")
            }
            if let match {
                sourceMap[key] = match.id
            } else {
                let source = LibrarySource(
                    kind: kind, title: raw["title"] as! String, url: url, assetHash: hash)
                sources.append(source)
                sourceMap[key] = source.id
                if [.pdf, .epub, .local_video].contains(kind) {
                    warnings.append("\(source.title)：尚未绑定本地资料，卡片仍可保留")
                }
            }
        }
        let sourceByID = Dictionary(uniqueKeysWithValues: (sources + existing.sources).map { ($0.id, $0) })
        for raw in rawCards {
            var card = LibraryCard(
                type: CardKind(rawValue: raw["type"] as! String)!,
                content: raw["content"] as! [String: String])
            card.discovery = .ai
            card.language = raw["language"] as! String
            card.tags = raw["tags"] as! [String]
            card.importAnnotation = raw["note"] as? String ?? ""
            var refMap: [String: UUID] = [:]
            for ref in raw["source_refs"] as! [[String: Any]] {
                let key = ref["id"] as! String
                guard refMap[key] == nil, let sourceID = sourceMap[ref["source_id"] as! String] else {
                    throw LibraryError.invalid("source_refs 编号重复或资料引用无效")
                }
                let rawLocator = ref["locator"] as? [String: Any]
                let locator = try rawLocator.map { value in
                    ReadingLocator(
                        kind: value["type"] as! String, page: value["file_page"] as? Int,
                        seconds: value["seconds"] as? Double, href: value["href"] as? String,
                        progression: value["progression"] as? Double, nativeJSON: try encode(value))
                }
                let source = sourceByID[sourceID]!
                if let locator {
                    let expected =
                        [.youtube, .local_video].contains(source.kind) ? "video" : source.kind.rawValue
                    guard locator.kind == expected else { throw LibraryError.invalid("定位类型与资料不匹配") }
                } else {
                    warnings.append("\(card.title)：缺失定位，暂不能回跳")
                }
                let mapped = CardReference(sourceID: sourceID, locator: locator)
                refMap[key] = mapped.id
                card.sourceRefs.append(mapped)
            }
            let rawProvenance = raw["provenance"] as! [String: Any]
            var fields = rawProvenance["fields"] as! [String: [String: Any]]
            if let note = rawProvenance["note"] as? [String: Any] { fields["import_annotation"] = note }
            if !card.importAnnotation.isEmpty && fields["import_annotation"] == nil {
                throw LibraryError.invalid("导入说明缺少 provenance")
            }
            guard card.content.keys.allSatisfy({ fields[$0] != nil }) else {
                throw LibraryError.invalid("内容字段缺少 provenance")
            }
            for (field, origin) in fields {
                let ids = try (origin["source_ref_ids"] as! [String]).map { id in
                    guard let mapped = refMap[id] else { throw LibraryError.invalid("字段出处引用不存在：\(field)") }
                    return mapped
                }
                card.provenance[field] = FieldOrigin(kind: origin["kind"] as! String, sourceRefIDs: ids)
            }
            cardMap[raw["id"] as! String] = card.id
            cards.append(card)
        }
        for raw in rawRelations {
            guard let from = cardMap[raw["from_card_id"] as! String],
                let to = cardMap[raw["to_card_id"] as! String], from != to
            else { throw LibraryError.invalid("关系引用无效") }
            var relation = LibraryRelation(from: from, to: to, kind: raw["type"] as! String)
            relation.note = raw["note"] as? String ?? ""
            relations.append(relation)
        }
        var combined = existing
        combined.sources += sources
        combined.cards += cards
        combined.relations += relations
        try combined.validate()
        let existingContent = Set(existing.cards.filter { $0.deletedAt == nil }.map(CardContentKey.init))
        let duplicateIDs = Set(cards.filter { existingContent.contains(CardContentKey($0)) }.map(\.id))
        return ImportPreview(
            packageID: packageID, title: root["title"] as! String, sources: sources, cards: cards,
            relations: relations, canonical: canonical, duplicateCardIDs: duplicateIDs, warnings: warnings)
    }

    public static func commit(
        _ preview: ImportPreview, selected: Set<UUID>, projectID: UUID?, pendingID: UUID?,
        to repository: LibraryRepository
    ) throws {
        try repository.update { state in
            guard state.importedPackages[preview.packageID] == nil else {
                throw LibraryError.invalid("此批次已处理，请刷新")
            }
            let chosen = preview.cards.filter { selected.contains($0.id) }
            guard !chosen.isEmpty else { throw LibraryError.invalid("至少选择一张候选卡片") }
            let needed = Set(chosen.flatMap { $0.sourceRefs.map(\.sourceID) })
            let available = Set(state.sources.filter { $0.deletedAt == nil }.map(\.id)).union(
                preview.sources.map(\.id))
            guard needed.isSubset(of: available) else { throw LibraryError.invalid("预览中的资料已被删除，请重新匹配") }
            for source in preview.sources where needed.contains(source.id) {
                if !state.sources.contains(where: { $0.id == source.id }) { state.sources.append(source) }
            }
            state.cards += chosen
            let keptRelations = preview.relations.filter {
                selected.contains($0.from) && selected.contains($0.to)
            }
            state.relations += keptRelations
            if let projectID {
                guard
                    let index = state.projects.firstIndex(where: { $0.id == projectID && $0.deletedAt == nil }
                    )
                else { throw LibraryError.invalid("所选项目不存在") }
                state.projects[index].cardIDs += chosen.map(\.id)
                state.projects[index].sourceIDs = Array(Set(state.projects[index].sourceIDs).union(needed))
                state.projects[index].relationIDs += keptRelations.map(\.id)
            }
            state.importedPackages[preview.packageID] = preview.canonical
            if let pendingID { state.pending.removeAll { $0.id == pendingID } }
        }
    }
    private static func encode(_ object: Any) throws -> String {
        String(
            data: try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
    }
}

private struct CardContentKey: Hashable {
    let type: CardKind
    let content: [String: String]
    let language: String
    init(_ card: LibraryCard) {
        type = card.type
        content = card.content
        language = card.language
    }
}

/// Foundation and OrderedJSON accept duplicate keys; reject them before schema validation.
private struct StrictJSON {
    var bytes: [UInt8]
    var index = 0
    static func check(_ data: Data) throws {
        _ = try JSONSerialization.jsonObject(with: data)
        var scanner = StrictJSON(bytes: Array(data))
        try scanner.value(depth: 0)
        scanner.space()
        guard scanner.index == scanner.bytes.count else { throw LibraryError.invalid("JSON 尾部有额外内容") }
    }
    mutating func space() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    mutating func string() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            if bytes[index] == 92 {
                index += 2
                continue
            }
            if bytes[index] == 34 {
                index += 1
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            }
            index += 1
        }
        throw LibraryError.invalid("JSON 字符串未结束")
    }
    mutating func value(depth: Int) throws {
        space()
        guard depth <= 64, index < bytes.count else { throw LibraryError.invalid("JSON 层级过深或不完整") }
        if bytes[index] == 34 {
            _ = try string()
            return
        }
        if bytes[index] == 123 {
            index += 1
            space()
            var keys: Set<String> = []
            if take(125) { return }
            while true {
                space()
                guard index < bytes.count, bytes[index] == 34 else {
                    throw LibraryError.invalid("JSON 字段格式无效或含尾逗号")
                }
                let key = try string()
                guard keys.insert(key).inserted else { throw LibraryError.invalid("JSON 重复字段：\(key)") }
                space()
                guard take(58) else { throw LibraryError.invalid("JSON 缺少冒号") }
                try value(depth: depth + 1)
                space()
                if take(125) { return }
                guard take(44) else { throw LibraryError.invalid("JSON 缺少逗号") }
            }
        }
        if bytes[index] == 91 {
            index += 1
            space()
            if take(93) { return }
            while true {
                try value(depth: depth + 1)
                space()
                if take(93) { return }
                guard take(44) else { throw LibraryError.invalid("JSON 数组格式无效") }
            }
        }
        let start = index
        while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        guard index > start else { throw LibraryError.invalid("JSON 值缺失或含尾逗号") }
        _ = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed)
    }
    mutating func take(_ token: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == token else { return false }
        index += 1
        return true
    }
}
