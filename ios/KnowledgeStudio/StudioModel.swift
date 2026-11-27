import CryptoKit
import KnowledgeCore
import SwiftUI
import Observation

@MainActor
@Observable
final class StudioModel {
    private(set) var state = LibraryState()
    private(set) var sources: [LibrarySource] = []
    private(set) var marks: [LibraryMark] = []
    private(set) var cards: [LibraryCard] = []
    private(set) var projects: [LibraryProject] = []
    private(set) var relations: [LibraryRelation] = []
    private(set) var pending: [PendingImport] = []
    private(set) var reviewRecords: [LibraryReviewRecord] = []
    private(set) var markIndex = LibraryMarkIndex([])
    var message: String?
    var sharedWarning: String?
    private(set) var isImporting = false
    private(set) var importStatus: String?
    private(set) var importCanCancel = false
    private(set) var sharedDocuments: [SharedDocumentInbox.Entry] = []
    @ObservationIgnored private var importTask: Task<LibrarySource, Error>?
    @ObservationIgnored private var changingManagedData = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var activeWrites = 0
    @ObservationIgnored private var writeWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var readerSaves: [UUID: Task<Void, Never>] = [:]
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
            // Foreground activation receives shared queues asynchronously once.
            publish(try repository!.read())
            try finishAssetPurge()
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
    @ObservationIgnored private var refreshing = false

    func refreshAsync() async {
        guard let repository, !refreshing else { return }
        refreshing = true
        let trace = PerformanceTrace.signposter.beginInterval("SafariReceive", id: PerformanceTrace.signposter.makeSignpostID())
        defer { refreshing = false; PerformanceTrace.signposter.endInterval("SafariReceive", trace) }
        do {
            try await Task.detached(priority: .utility) {
                try repository.receive(WebMarkStore.configured().readAll())
                try repository.receivePages(PageCaptureStore.configured().readAll())
            }.value
            sharedWarning = nil
        } catch {
            sharedWarning = "Safari 交接未完成：\(error.localizedDescription)"
        }
        do { try await reloadAsync(repository) }
        catch { message = error.localizedDescription }
    }

    private func publish(_ snapshot: LibraryState) {
        guard snapshot != state else { return }
        revision += 1
        state = snapshot
        // Separate dependencies: a reading-position change must not invalidate a
        // card-only screen or rebuild the reader's mark index.
        if sources != snapshot.sources { sources = snapshot.sources }
        if marks != snapshot.marks { marks = snapshot.marks; markIndex = LibraryMarkIndex(snapshot.marks) }
        if cards != snapshot.cards { cards = snapshot.cards }
        if projects != snapshot.projects { projects = snapshot.projects }
        if relations != snapshot.relations { relations = snapshot.relations }
        if pending != snapshot.pending { pending = snapshot.pending }
        if reviewRecords != snapshot.reviewRecords { reviewRecords = snapshot.reviewRecords }
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
    private func commitAsync(_ action: @escaping @Sendable (inout LibraryState) throws -> Void) async throws {
        guard let repository else { throw LibraryError.invalid("知识库不可用") }
        activeWrites += 1
        defer {
            activeWrites -= 1
            if activeWrites == 0 {
                let waiters = writeWaiters
                writeWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        let trace = PerformanceTrace.signposter.beginInterval("LibraryCommit", id: PerformanceTrace.signposter.makeSignpostID())
        defer { PerformanceTrace.signposter.endInterval("LibraryCommit", trace) }
        let background = LibrarySaveAssertion()
        defer { background.end() }
        let before = revision
        let committed = try await Task.detached(priority: .userInitiated) {
            try repository.updateAndRead(action)
        }.value
        if revision == before { publish(committed); return }
        try await reloadAsync(repository)
    }

    private func reloadAsync(_ repository: LibraryRepository) async throws {
        while true {
            let observed = revision
            let latest = try await Task.detached { try repository.read() }.value
            if revision == observed { publish(latest); return }
        }
    }

    func saveCard(_ card: LibraryCard, projects: Set<UUID>? = nil) {
        change { Self.writeCard(card, projects: projects, to: &$0) }
    }

    func saveEditedCard(_ card: LibraryCard, projects: Set<UUID>, inboxMark: UUID?) async throws {
        try await commitAsync { state in
            if let inboxMark {
                guard let markIndex = state.marks.firstIndex(where: {
                    $0.id == inboxMark && $0.deletedAt == nil && $0.organization == .inbox
                }) else { throw LibraryError.invalid("这条摘录已处理，请返回收集箱。") }
                if let existing = state.cards.first(where: { $0.markIDs.contains(inboxMark) }) {
                    guard existing.deletedAt == nil && existing.id == card.id else {
                        throw LibraryError.invalid("此摘录已有卡片。若卡片在回收站，请先恢复。")
                    }
                }
                Self.writeCard(card, projects: projects, to: &state)
                state.marks[markIndex].organization = .archived
            } else {
                Self.writeCard(card, projects: projects, to: &state)
            }
        }
    }

    nonisolated private static func writeCard(_ card: LibraryCard, projects: Set<UUID>?,
        to state: inout LibraryState)
    {
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

    func renameSource(_ id: UUID, title: String) {
        change { state in
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let index = state.sources.firstIndex(where: { $0.id == id && $0.deletedAt == nil })
            else { throw LibraryError.invalid("请输入资料名称。") }
            state.sources[index].title = title
            state.sources[index].updatedAt = .now
        }
    }

    func suggestedProjects(for card: LibraryCard) -> Set<UUID> {
        let exists = state.cards.contains { $0.id == card.id }
        let sourceIDs = Set(card.sourceRefs.map(\.sourceID))
        return Set(state.projects.filter { project in
            project.deletedAt == nil && (exists
                ? project.cardIDs.contains(card.id)
                : !sourceIDs.isDisjoint(with: project.sourceIDs))
        }.map(\.id))
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
    /// Register autosaves before returning from the reader callback. Export and
    /// restore can then wait for them even before their async bodies have started.
    func scheduleReaderSave(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let background = LibrarySaveAssertion()
        readerSaves[id] = Task {
            await operation()
            background.end()
            readerSaves.removeValue(forKey: id)
        }
    }

    func flushReaderWrites() async throws {
        while true {
            while let task = readerSaves.values.first { await task.value }
            try await flushReadingPositions()
            while activeWrites > 0 { await withCheckedContinuation { writeWaiters.append($0) } }
            if readerSaves.isEmpty && pendingPositions.isEmpty { return }
        }
    }

    func saveMarkAsync(source: LibrarySource, locator: ReadingLocator, excerpt: String = "", kind: CardKind? = nil) async throws {
        var mark = LibraryMark(sourceID: source.id, locator: locator, excerpt: excerpt)
        mark.cardKind = kind
        try await saveReaderMark(mark, updatePosition: true)
    }

    func saveReaderMark(_ mark: LibraryMark, updatePosition: Bool) async throws {
        message = nil
        try await commitAsync { state in
            guard let index = state.sources.firstIndex(where: { $0.id == mark.sourceID && $0.deletedAt == nil })
            else { throw LibraryError.invalid("原资料已不可用，标记未写入") }
            state.marks.append(mark)
            if updatePosition, (state.sources[index].lastReadAt ?? .distantPast) <= mark.createdAt {
                state.sources[index].lastLocation = mark.locator
                state.sources[index].lastReadAt = mark.createdAt
            }
        }
    }

    func savePDFInk(sourceID: UUID, fingerprint: String, page: Int, drawing: Data?, expected: Data?) async throws {
        try await commitAsync { state in
            guard let index = state.sources.firstIndex(where: {
                $0.id == sourceID && $0.deletedAt == nil && $0.assetHash == fingerprint
            }) else { throw LibraryError.invalid("原始 PDF 已变更，笔迹未写入") }
            var entries = state.sources[index].pdfPageInk ?? []
            let entry = entries.firstIndex { $0.page == page && $0.fingerprint == fingerprint }
            guard entry.map({ entries[$0].drawing }) == expected else {
                throw LibraryError.invalid("此页笔迹已在另一窗口更新，未覆盖已保存笔迹")
            }
            if let entry { entries.remove(at: entry) }
            if let drawing { entries.append(PDFPageInk(fingerprint: fingerprint, page: page, drawing: drawing)) }
            state.sources[index].pdfPageInk = entries.isEmpty ? nil : entries
        }
    }

    func saveEPUBInk(mark: LibraryMark, drawing: Data?) async throws {
        message = nil
        try await commitAsync { state in
            guard let index = state.marks.firstIndex(where: {
                $0.id == mark.id && $0.deletedAt == nil && $0.locator == mark.locator
            }), state.marks[index].epubNoteInk == mark.epubNoteInk else {
                throw LibraryError.invalid("原批注已变更，未覆盖已保存内容")
            }
            state.marks[index].epubNoteInk = drawing
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
    private struct ReadingPosition: Sendable {
        let locator: ReadingLocator
        let date: Date
    }
    @ObservationIgnored private var pendingPositions: [UUID: ReadingPosition] = [:]
    @ObservationIgnored private var readingWriteTask: Task<Void, Never>?
    @ObservationIgnored private var readingFailure: Error?

    /// Coalesce only replaceable resume positions. Marks, ink and edits retain
    /// their durable transactional APIs. A single drain bounds concurrent work.
    func queueReadingPosition(sourceID: UUID, locator: ReadingLocator) {
        if readingWriteTask == nil, pendingPositions[sourceID] == nil,
            let source = sources.first(where: { $0.id == sourceID }), source.lastLocation == locator,
            let read = source.lastReadAt, Date().timeIntervalSince(read) < 60 { return }
        pendingPositions[sourceID] = ReadingPosition(locator: locator, date: .now)
        startReadingWrites()
    }

    private func startReadingWrites() {
        guard readingWriteTask == nil, !pendingPositions.isEmpty else { return }
        readingFailure = nil
        readingWriteTask = Task { await drainReadingPositions() }
    }

    private func drainReadingPositions() async {
        // Keep an in-flight save alive when the reader closes or the App resigns
        // active. Expiration ends the OS assertion, never cancels a transaction.
        let background = LibrarySaveAssertion()
        defer {
            readingWriteTask = nil
            background.end()
        }
        while !pendingPositions.isEmpty {
            let batch = pendingPositions
            pendingPositions.removeAll()
            do {
                try await commitAsync { state in
                    for index in state.sources.indices {
                        guard let position = batch[state.sources[index].id], state.sources[index].deletedAt == nil else { continue }
                        // A newer explicit edit/mark or another window wins over an
                        // old position waiting for the writer connection.
                        guard (state.sources[index].lastReadAt ?? .distantPast) <= position.date else { continue }
                        state.sources[index].lastLocation = position.locator
                        state.sources[index].lastReadAt = position.date
                    }
                }
            } catch {
                for (id, position) in batch where pendingPositions[id] == nil { pendingPositions[id] = position }
                readingFailure = error
                message = "阅读位置尚未保存，将在下次保存时重试：\(error.localizedDescription)"
                return
            }
        }
    }

    /// Export/restore and lifecycle tests can wait for durable state, not merely
    /// an enqueued UI update. Failed positions remain available for retry.
    func flushReadingPositions() async throws {
        startReadingWrites()
        while let task = readingWriteTask { await task.value }
        if let readingFailure { throw readingFailure }
    }

    func assetURL(_ source: LibrarySource) -> URL? {
        guard let hash = source.assetHash, let ext = source.assetExtension else { return nil }
        return root.appendingPathComponent("assets/\(hash).\(ext)")
    }
    func reloadSharedDocuments() async {
        sharedDocuments = (try? await Task.detached(priority: .utility) {
            try SharedDocumentInbox.configured().entries()
        }.value) ?? []
    }

    func acceptSharedDocument(_ entry: SharedDocumentInbox.Entry) async {
        guard !isImporting else { return }
        do {
            let inbox = try SharedDocumentInbox.configured()
            let file = try inbox.file(entry)
            if await importFile(file) {
                try inbox.remove(entry)
            }
        } catch { message = error.localizedDescription }
        await reloadSharedDocuments()
    }

    func cancelImport() {
        importTask?.cancel()
        importCanCancel = false
    }

    @discardableResult
    func importFile(_ url: URL, replacing sourceID: UUID? = nil, projectID: UUID? = nil) async -> Bool {
        guard !isImporting, !changingManagedData else {
            message = "资料库正在处理另一项任务，请稍后重试。"
            return false
        }
        isImporting = true
        importStatus = "正在接收「\(url.lastPathComponent)」"
        message = nil
        importCanCancel = true
        defer { isImporting = false; importCanCancel = false; importTask = nil }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            guard repository != nil else { throw LibraryError.invalid("知识库不可用") }
            let root = self.root
            let copy = Task.detached(priority: .userInitiated) {
                try Self.prepareAsset(url: url, root: root)
            }
            importTask = copy
            let imported = try await withTaskCancellationHandler {
                try await copy.value
            } onCancel: { copy.cancel() }
            try Task.checkCancellation()
            guard !copy.isCancelled else { throw CancellationError() }
            importTask = nil
            importCanCancel = false
            importStatus = "正在写入资料库…"
            let wasExisting = state.sources.contains { $0.assetHash == imported.assetHash && $0.deletedAt == nil }
            try await commitAsync { state in
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
                    if existing == nil && state.sources.contains(where: { $0.assetHash == imported.assetHash }) {
                        throw LibraryError.invalid("这份资料在回收站，请先恢复。")
                    }
                    let id = existing?.id ?? imported.id
                    if existing == nil { state.sources.append(imported) }
                    if let projectID {
                        guard let index = state.projects.firstIndex(where: {
                            $0.id == projectID && $0.deletedAt == nil
                        }) else { throw LibraryError.invalid("目标项目已不可用，请重新选择。") }
                        if !state.projects[index].sourceIDs.contains(id) {
                            state.projects[index].sourceIDs.append(id)
                        }
                    }
                }
            }
            message = nil
            importStatus = wasExisting
                ? (projectID == nil ? "这份资料已在资料库。" : "已将现有资料关联到所选项目。")
                : "已导入「\(imported.title)」"
            return true
        } catch is CancellationError {
            importStatus = "导入已取消。"
            return false
        } catch {
            importStatus = "资料未导入"
            message = error.localizedDescription
            return false
        }
    }

    /// Copy and hash in bounded chunks off the UI actor, then publish an immutable asset.
    nonisolated private static func prepareAsset(url: URL, root: URL) throws -> LibrarySource {
        try Task.checkCancellation()
        let ext = url.pathExtension.lowercased()
        guard SharedDocumentInbox.extensions.contains(ext) else {
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
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
            digest.update(data: chunk)
        }
        try output.close()
        try Task.checkCancellation()
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let destination = root.appendingPathComponent("assets/\(hash).\(ext)")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Self.hash(destination) == hash else { throw LibraryError.invalid("现有资料摘要不符，拒绝覆盖") }
        } else {
            guard try Self.hash(stage) == hash else { throw LibraryError.invalid("资料复制校验失败，未加入资料库") }
            try Task.checkCancellation()
            do { try FileManager.default.moveItem(at: stage, to: destination) } catch CocoaError
                .fileWriteFileExists
            {
                guard try Self.hash(destination) == hash else { throw LibraryError.invalid("并发导入的资料摘要不符") }
            }
        }
        let kind: SourceKind = ext == "pdf" ? .pdf : ext == "epub" ? .epub : .local_video
        return LibrarySource(
            kind: kind, title: Self.importTitle(url.deletingPathExtension().lastPathComponent), assetHash: hash,
            assetExtension: ext)
    }

    nonisolated static func importTitle(_ sourceName: String) -> String {
        let cleaned = sourceName.replacingOccurrences(
            of: #"\s*[\(（]\s*(?:z[- ]?library|1lib|b[- ]?ok|libgen|annas[- ]archive)\b[^()（）]*[\)）]\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? sourceName : cleaned
    }

    nonisolated static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    @discardableResult
    func stageImport(_ text: String) async -> PendingImport? {
        do {
            let snapshot = state
            let preview = try await Task.detached(priority: .userInitiated) {
                try ImportService.preview(text, existing: snapshot)
            }.value
            try await commitAsync { state in
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
            return state.pending.first { $0.packageID == preview.packageID }
        } catch { message = error.localizedDescription; return nil }
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
    private var purgeJournal: URL { root.appendingPathComponent("pending-asset-purge.json") }

    private func finishAssetPurge() throws {
        guard FileManager.default.fileExists(atPath: purgeJournal.path) else { return }
        let names = Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: purgeJournal)))
        do {
            for file in try unusedAssets() where names.contains(file.lastPathComponent) {
                try FileManager.default.removeItem(at: file)
            }
            try FileManager.default.removeItem(at: purgeJournal)
        } catch {
            throw LibraryError.invalid("资料文件清理未完成，下次打开时会重试：\(error.localizedDescription)")
        }
    }

    func commitImport(_ preview: ImportPreview, selected: Set<UUID>, projectID: UUID?, pendingID: UUID) async throws {
        guard let repository else { throw LibraryError.invalid("知识库不可用") }
        try await Task.detached(priority: .userInitiated) {
            try ImportService.commit(preview, selected: selected, projectID: projectID, pendingID: pendingID, to: repository)
        }.value
        try await reloadAsync(repository)
    }

    func reviewCard(_ cardID: UUID, rating: Int, expectedRevision: Int?, eventID: UUID,
        elapsedMilliseconds: Int, retention: Double) async throws
    {
        guard let repository else { throw LibraryError.invalid("知识库不可用") }
        try await Task.detached(priority: .userInitiated) {
            try repository.recordReview(cardID: cardID, rating: rating, expectedRevision: expectedRevision,
                eventID: eventID, elapsedMilliseconds: elapsedMilliseconds, retention: retention)
        }.value
        try await reloadAsync(repository)
    }

    func deleteManaged(_ ids: Set<UUID>, restore: Bool = false, permanently: Bool = false) async -> Bool {
        guard !ids.isEmpty, !changingManagedData else { return false }
        changingManagedData = true
        defer { changingManagedData = false }
        message = nil
        do {
            if permanently {
                guard !isImporting else { throw LibraryError.invalid("等待资料导入完成后再永久清理。") }
                try stageAssetPurge(ids)
            }
            try await commitAsync { state in
                if permanently { try Self.purge(ids, in: &state) }
                else { try Self.setTrashed(ids, restored: restore, in: &state) }
            }
            if permanently { try finishAssetPurge() }
            do {
                try await Task.detached(priority: .utility) {
                    try Self.syncWebDeletion(ids, restore: restore)
                }.value
            } catch { sharedWarning = "本地操作已完成，Safari 状态更新失败：\(error.localizedDescription)" }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func stageAssetPurge(_ ids: Set<UUID>) throws {
        try finishAssetPurge()
        let names = state.sources.filter { ids.contains($0.id) && $0.deletedAt != nil }
            .compactMap { assetURL($0)?.lastPathComponent }
        if !names.isEmpty {
            try JSONEncoder().encode(names).write(to: purgeJournal, options: .atomic)
        }
    }

    nonisolated private static func syncWebDeletion(_ ids: Set<UUID>, restore: Bool) throws {
        guard let store = try? WebMarkStore.configured() else { return }
        for mark in try store.readAll() where ids.contains(mark.id) {
            try store.annotate(id: mark.id, deleted: !restore)
        }
    }

    func delete(_ ids: Set<UUID>, restore: Bool = false, permanently: Bool = false) {
        guard !ids.isEmpty else { return }
        message = nil
        do {
            if permanently {
                guard !isImporting else { throw LibraryError.invalid("资料正在导入，请稍后清理。") }
                try stageAssetPurge(ids)
            }
            try commit { state in
                if permanently { try Self.purge(ids, in: &state) }
                else { try Self.setTrashed(ids, restored: restore, in: &state) }
            }
            if permanently { try finishAssetPurge() }
        } catch { message = error.localizedDescription }
        if message == nil {
            do { try Self.syncWebDeletion(ids, restore: restore) }
            catch { sharedWarning = "本地操作已完成，Safari 状态更新失败：\(error.localizedDescription)" }
        }
    }

    nonisolated private static func trashIDs(in state: LibraryState) -> Set<UUID> {
        var ids = Set(state.sources.filter { $0.deletedAt != nil }.map(\.id))
        ids.formUnion(state.marks.filter { $0.deletedAt != nil }.map(\.id))
        ids.formUnion(state.cards.filter { $0.deletedAt != nil }.map(\.id))
        ids.formUnion(state.projects.filter { $0.deletedAt != nil }.map(\.id))
        ids.formUnion(state.relations.filter { $0.deletedAt != nil }.map(\.id))
        ids.formUnion(state.reviewRecords.filter { $0.deletedAt != nil }.map(\.id))
        ids.formUnion(state.projects.filter { $0.hasBoard && $0.boardTrashedAt != nil }.map(\.boardManagementID))
        return ids
    }

    nonisolated private static func purge(_ ids: Set<UUID>, in state: inout LibraryState) throws {
        guard ids.isSubset(of: trashIDs(in: state)) else { throw LibraryError.invalid("请先移入回收站。") }
        for id in ids {
            let linkedCards = state.cards.contains { card in
                !ids.contains(card.id) && (card.markIDs.contains(id) || card.sourceRefs.contains { $0.sourceID == id })
            }
            let linkedProjects = state.projects.contains { project in
                !ids.contains(project.id) && project.references(id, includingBoard: !ids.contains(project.boardManagementID))
            }
            let linkedMarks = state.marks.contains { !ids.contains($0.id) && $0.sourceID == id }
            let linkedReviews = state.reviewRecords.contains { !ids.contains($0.id) && $0.cardID == id }
            let linkedRelations = state.relations.contains { relation in
                !ids.contains(relation.id) && (relation.from == id || relation.to == id)
            }
            if linkedCards || linkedProjects || linkedMarks || linkedReviews || linkedRelations {
                throw LibraryError.invalid("对象仍被引用，请先解除关联或清理引用对象")
            }
        }
        for index in state.projects.indices where ids.contains(state.projects[index].boardManagementID) {
            state.projects[index].board = nil
            state.projects[index].boardCoverImage = nil
            state.projects[index].boardTrashedAt = nil
        }
        state.reviewRecords.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
        state.sources.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
        state.marks.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
        state.cards.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
        state.projects.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
        state.relations.removeAll { ids.contains($0.id) && $0.deletedAt != nil }
    }

    nonisolated private static func setTrashed(_ ids: Set<UUID>, restored restore: Bool,
        in state: inout LibraryState) throws
    {
        let date: Date? = restore ? nil : Date()
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
        for index in state.projects.indices where state.projects[index].hasBoard &&
            ids.contains(state.projects[index].boardManagementID) {
            if restore && state.projects[index].deletedAt != nil {
                throw LibraryError.invalid("请先恢复白板所属项目。")
            }
            state.projects[index].boardTrashedAt = date
        }
    }

}

@MainActor
private final class LibrarySaveAssertion {
    private var identifier = UIBackgroundTaskIdentifier.invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Library save") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
