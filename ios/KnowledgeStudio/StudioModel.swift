import CryptoKit
import KnowledgeCore
import SwiftUI

@MainActor
final class StudioModel: ObservableObject {
    @Published private(set) var state = LibraryState()
    @Published var message: String?
    @Published var sharedWarning: String?
    @Published private(set) var isImporting = false
    let root: URL
    private(set) var repository: LibraryRepository?

    init(root: URL? = nil) {
        self.root =
            root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KnowledgeStudio")
        do {
            repository = try LibraryRepository(url: self.root.appendingPathComponent("library.sqlite"))
            try repository?.migratePrototype(at: self.root.appendingPathComponent("prototype-v1.json"))
            refresh()
        } catch { message = "知识库未打开，原文件已保留：\(error.localizedDescription)" }
    }
    func perform(_ action: () throws -> Void) {
        message = nil
        do {
            guard repository != nil else { throw LibraryError.invalid("知识库不可用，禁止写入") }
            try action()
            publish(try repository!.read())
        } catch { message = error.localizedDescription }
    }
    func refresh() {
        perform {
            do {
                try repository!.receive(WebMarkStore.configured().readAll())
                try repository!.receivePages(PageCaptureStore.configured().readAll())
                if sharedWarning != nil { sharedWarning = nil }
            } catch {
                let warning = "Safari 交接未完成：\(error.localizedDescription)"
                if sharedWarning != warning { sharedWarning = warning }
            }
        }
    }
    private func publish(_ snapshot: LibraryState) {
        if snapshot != state { state = snapshot }
    }

    func commit(_ action: (inout LibraryState) throws -> Void) throws {
        guard let repository else { throw LibraryError.invalid("知识库不可用，禁止写入") }
        publish(try repository.updateAndRead(action))
    }

    func change(_ action: (inout LibraryState) throws -> Void) {
        message = nil
        do { try commit(action) }
        catch { message = error.localizedDescription }
    }
    func saveCard(_ card: LibraryCard, projects: Set<UUID>? = nil) {
        change { state in
            if let index = state.cards.firstIndex(where: { $0.id == card.id }) {
                var edited = card
                edited.schedule = state.cards[index].schedule
                state.cards[index] = edited
            } else {
                state.cards.append(card)
            }
            if let projects {
                for index in state.projects.indices where state.projects[index].deletedAt == nil {
                    if projects.contains(state.projects[index].id) {
                        if !state.projects[index].cardIDs.contains(card.id) {
                            state.projects[index].cardIDs.append(card.id)
                        }
                    } else {
                        state.projects[index].cardIDs.removeAll { $0 == card.id }
                    }
                }
            }
        }
    }
    func card(from mark: LibraryMark, type: CardKind) -> LibraryCard {
        let field = LibraryCard.fields(for: type)[0]
        var card = LibraryCard(type: type, content: [field: mark.excerpt])
        let ref = CardReference(sourceID: mark.sourceID, locator: mark.locator)
        card.sourceRefs = [ref]
        card.markIDs = [mark.id]
        if !mark.excerpt.isEmpty {
            card.provenance[field] = FieldOrigin(kind: "original", sourceRefIDs: [ref.id])
        }
        return card
    }
    func saveMark(source: LibrarySource, locator: ReadingLocator, excerpt: String = "", kind: CardKind? = nil)
    {
        change { state in
            var mark = LibraryMark(sourceID: source.id, locator: locator, excerpt: excerpt)
            mark.cardKind = kind
            state.marks.append(mark)
            if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                state.sources[index].lastLocation = locator
                state.sources[index].lastReadAt = Date()
            }
        }
    }
    func saveLocation(sourceID: UUID, locator: ReadingLocator) {
        if let source = state.sources.first(where: { $0.id == sourceID }), source.lastLocation == locator,
            let read = source.lastReadAt, Date().timeIntervalSince(read) < 60
        {
            return
        }
        change { state in
            if let index = state.sources.firstIndex(where: { $0.id == sourceID }) {
                state.sources[index].lastLocation = locator
                state.sources[index].lastReadAt = Date()
            }
        }
    }
    func assetURL(_ source: LibrarySource) -> URL? {
        guard let hash = source.assetHash, let ext = source.assetExtension else { return nil }
        return root.appendingPathComponent("assets/\(hash).\(ext)")
    }
    func importFile(_ url: URL, replacing sourceID: UUID? = nil, projectID: UUID? = nil) async {
        guard !isImporting else {
            message = "正在导入另一份资料，请稍后重试。"
            return
        }
        isImporting = true
        defer { isImporting = false }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            guard repository != nil else { throw LibraryError.invalid("知识库不可用") }
            let root = self.root
            let imported = try await Task.detached(priority: .userInitiated) {
                try Self.prepareAsset(url: url, root: root)
            }.value
            change { state in
                if let sourceID {
                    guard
                        let index = state.sources.firstIndex(where: {
                            $0.id == sourceID && $0.deletedAt == nil
                        }),
                        state.sources[index].kind == imported.kind,
                        state.sources[index].assetHash == nil
                            || state.sources[index].assetHash == imported.assetHash
                    else {
                        throw LibraryError.invalid("原资料不存在、类型或摘要不匹配，未替换")
                    }
                    state.sources[index].assetHash = imported.assetHash
                    state.sources[index].assetExtension = imported.assetExtension
                } else {
                    let existing = state.sources.first {
                        $0.assetHash == imported.assetHash && $0.deletedAt == nil
                    }
                    let id = existing?.id ?? imported.id
                    if existing == nil { state.sources.append(imported) }
                    if let projectID, let index = state.projects.firstIndex(where: {
                        $0.id == projectID && $0.deletedAt == nil
                    }), !state.projects[index].sourceIDs.contains(id) {
                        state.projects[index].sourceIDs.append(id)
                    }
                }
            }
        } catch { message = error.localizedDescription }
    }

    /// Copy and hash in bounded chunks off the UI actor, then publish an immutable asset.
    nonisolated private static func prepareAsset(url: URL, root: URL) throws -> LibrarySource {
        let ext = url.pathExtension.lowercased()
        guard ["pdf", "epub", "mp4", "m4v", "mov"].contains(ext) else {
            throw LibraryError.invalid("请选择 PDF、EPUB 或本地视频文件")
        }
        let stage = root.appendingPathComponent("asset-import-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: stage.path, contents: nil) else {
            throw LibraryError.invalid("无法创建资料临时文件")
        }
        defer { try? FileManager.default.removeItem(at: stage) }
        let input = try FileHandle(forReadingFrom: url)
        let output = try FileHandle(forWritingTo: stage)
        defer {
            try? input.close()
            try? output.close()
        }
        var digest = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
            digest.update(data: chunk)
        }
        try output.close()
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard try Self.hash(stage) == hash else { throw LibraryError.invalid("资料复制校验失败，未加入资料库") }
        let destination = root.appendingPathComponent("assets/\(hash).\(ext)")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Self.hash(destination) == hash else { throw LibraryError.invalid("现有资料摘要不符，拒绝覆盖") }
        } else {
            do { try FileManager.default.moveItem(at: stage, to: destination) } catch CocoaError
                .fileWriteFileExists
            {
                guard try Self.hash(destination) == hash else { throw LibraryError.invalid("并发导入的资料摘要不符") }
            }
        }
        let kind: SourceKind = ext == "pdf" ? .pdf : ext == "epub" ? .epub : .local_video
        return LibrarySource(
            kind: kind, title: url.deletingPathExtension().lastPathComponent, assetHash: hash,
            assetExtension: ext)
    }

    nonisolated static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func stageImport(_ text: String) async {
        do {
            let snapshot = state
            let preview = try await Task.detached(priority: .userInitiated) {
                try ImportService.preview(text, existing: snapshot)
            }.value
            try commit { state in
                if state.pending.contains(where: { $0.packageID == preview.packageID && $0.json != text }) {
                    throw LibraryError.invalid("导入箱已有同编号的不同批次")
                }
                guard !state.pending.contains(where: { $0.packageID == preview.packageID }) else { return }
                guard state.importedPackages[preview.packageID] == nil else {
                    throw LibraryError.invalid("该批次已导入")
                }
                state.pending.append(
                    PendingImport(packageID: preview.packageID, title: preview.title, json: text))
            }
            message = nil
        } catch { message = error.localizedDescription }
    }
    func unusedAssets() throws -> [URL] {
        var protected = Set(state.sources.compactMap { assetURL($0)?.lastPathComponent })
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where file.lastPathComponent.hasPrefix("before-restore-") {
            let snapshot = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: file))
            try snapshot.validate()
            protected.formUnion(snapshot.sources.compactMap { assetURL($0)?.lastPathComponent })
        }
        let assets = root.appendingPathComponent("assets")
        guard FileManager.default.fileExists(atPath: assets.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: assets, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { file in
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true
                && !protected.contains(file.lastPathComponent)
        }
    }
    func cleanUnusedAssets(_ selected: Set<URL>) {
        guard !isImporting else { message = "资料正在导入，请在导入完成后清理。"; return }
        perform {
            let stillUnused = Set(try unusedAssets())
            guard selected.isSubset(of: stillUnused) else {
                throw LibraryError.invalid("部分文件的引用已经变化，请重新检查清理项。")
            }
            for file in selected { try FileManager.default.removeItem(at: file) }
        }
    }

    func setMarkNote(id: UUID, note: String) {
        perform {
            if let web = try? WebMarkStore.configured().readAll(), web.contains(where: { $0.id == id }) {
                try WebMarkStore.configured().annotate(id: id, note: note)
                try repository!.receive(WebMarkStore.configured().readAll())
            } else {
                try repository!.update { state in
                    if let index = state.marks.firstIndex(where: { $0.id == id }) {
                        state.marks[index].note = note
                    }
                }
            }
        }
    }

    func impact(of id: UUID) -> String {
        let cards = state.cards.filter {
            $0.markIDs.contains(id) || $0.sourceRefs.contains { $0.sourceID == id }
        }.count
        let marks = state.marks.filter { $0.sourceID == id }.count
        let relations = state.relations.filter { $0.from == id || $0.to == id }.count
        let projects = state.projects.filter {
            $0.references(id)
        }.count
        return "关联卡片 \(cards)、标记 \(marks)、关系 \(relations)、项目 \(projects)。移入回收站保留关联；永久清理仅允许没有引用的对象。"
    }
    func delete(_ ids: Set<UUID>, restore: Bool = false, permanently: Bool = false) {
        change { state in
            if permanently {
                for id in ids {
                    let linked =
                        state.reviewRecords.contains { $0.cardID == id }
                        || state.marks.contains { $0.sourceID == id }
                        || state.cards.contains {
                            $0.markIDs.contains(id) || $0.sourceRefs.contains { $0.sourceID == id }
                        } || state.relations.contains { $0.from == id || $0.to == id }
                        || state.projects.contains {
                            $0.references(id)
                        }
                    guard !linked else { throw LibraryError.invalid("对象仍被引用，请先解除关联或清理引用对象") }
                }
                state.reviewRecords.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
                state.sources.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
                state.marks.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
                state.cards.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
                state.projects.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
                state.relations.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
            } else {
                let date: Date? = restore ? nil : Date()
                for index in state.reviewRecords.indices where ids.contains(state.reviewRecords[index].id) {
                    if restore {
                        guard
                            state.cards.contains(where: {
                                $0.id == state.reviewRecords[index].cardID && $0.deletedAt == nil
                            })
                        else { throw LibraryError.invalid("请先恢复复习记录所属卡片") }
                    }
                    state.reviewRecords[index].deletedAt = date
                }
                for index in state.sources.indices where ids.contains(state.sources[index].id) {
                    state.sources[index].deletedAt = date
                }
                for index in state.marks.indices where ids.contains(state.marks[index].id) {
                    if restore {
                        guard
                            state.sources.contains(where: {
                                $0.id == state.marks[index].sourceID && $0.deletedAt == nil
                            })
                        else { throw LibraryError.invalid("请先恢复标记的资料") }
                    }
                    state.marks[index].deletedAt = date
                }
                for index in state.cards.indices where ids.contains(state.cards[index].id) {
                    if restore {
                        guard
                            state.cards[index].sourceRefs.allSatisfy({ ref in
                                state.sources.contains { $0.id == ref.sourceID && $0.deletedAt == nil }
                            }),
                            state.cards[index].markIDs.allSatisfy({ id in
                                state.marks.contains { $0.id == id && $0.deletedAt == nil }
                            })
                        else { throw LibraryError.invalid("请先恢复卡片出处") }
                    }
                    state.cards[index].deletedAt = date
                }
                for index in state.relations.indices where ids.contains(state.relations[index].id) {
                    if restore {
                        guard
                            [state.relations[index].from, state.relations[index].to].allSatisfy({ id in
                                state.cards.contains { $0.id == id && $0.deletedAt == nil }
                            })
                        else { throw LibraryError.invalid("请先恢复关系端点") }
                    }
                    state.relations[index].deletedAt = date
                }
                for index in state.projects.indices where ids.contains(state.projects[index].id) {
                    state.projects[index].deletedAt = date
                }
            }
        }
        if message == nil, let web = try? WebMarkStore.configured().readAll() {
            for mark in web where ids.contains(mark.id) {
                do { try WebMarkStore.configured().annotate(id: mark.id, deleted: !restore) } catch {
                    sharedWarning = "本地操作已完成，Safari 状态更新失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
