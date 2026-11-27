import FSRS
import Foundation

/// Adapter payload is versioned independently of the knowledge card and preserved in every review record.
public struct ReviewSchedule: Codable, Equatable, Sendable {
    public var version = "swift-fsrs/6.0.0:FSRS-6"
    public var revision = 0
    public var due: Date
    public var engineState: Data
    public var parameters: Data
    public init(now: Date = Date(), retention: Double = 0.9) throws {
        guard (0.7...0.97).contains(retention) else { throw LibraryError.invalid("目标保持率应在 70% 至 97% 之间") }
        let card = FSRSDefaults().createEmptyCard(now: now)
        due = card.due
        engineState = try JSONEncoder().encode(card)
        parameters = try JSONEncoder().encode(
            FSRSParameters(requestRetention: retention, w: FSRSDefaults.defaultWv6, enableFuzz: false))
    }
    public var retention: Double {
        // Keep third-party Codable metadata inside KnowledgeCore. Release cross-
        // module inlining otherwise makes the App link FSRS implementation symbols.
        @inline(never) get {
            (try? JSONDecoder().decode(FSRSParameters.self, from: parameters).requestRetention) ?? 0.9
        }
    }
    public func validate() throws {
        guard version == "swift-fsrs/6.0.0:FSRS-6", revision >= 0 else {
            throw LibraryError.invalid("未知调度版本，保留数据并停止调度")
        }
        let card = try JSONDecoder().decode(Card.self, from: engineState)
        let params = try JSONDecoder().decode(FSRSParameters.self, from: parameters)
        guard due == card.due, due.timeIntervalSince1970.isFinite,
            card.stability.isFinite, card.stability >= 0, card.difficulty.isFinite,
            params.w.count == 21, params.w.allSatisfy(\.isFinite),
            (0.7...0.97).contains(params.requestRetention)
        else { throw LibraryError.invalid("调度状态或参数无效") }
    }
    public mutating func setRetention(_ retention: Double) throws {
        guard (0.7...0.97).contains(retention) else { throw LibraryError.invalid("目标保持率无效") }
        var params = try JSONDecoder().decode(FSRSParameters.self, from: parameters)
        params.requestRetention = retention
        parameters = try JSONEncoder().encode(params)
        try validate()
    }
}

extension LibraryRepository {
    public func recordReview(
        cardID: UUID, rating: Int, expectedRevision: Int?, eventID: UUID,
        now: Date = Date(), elapsedMilliseconds: Int = 0, retention: Double = 0.9
    ) throws {
        try update { state in
            if let prior = state.reviewRecords.first(where: { $0.id == eventID }) {
                guard prior.cardID == cardID && prior.rating == rating else {
                    throw LibraryError.invalid("复习记录编号冲突")
                }
                return
            }
            guard
                let index = state.cards.firstIndex(where: {
                    $0.id == cardID && $0.deletedAt == nil && $0.review == .active
                }),
                let grade = Rating(rawValue: rating), rating >= 1, rating <= 4,
                elapsedMilliseconds >= 0, now.timeIntervalSince1970.isFinite
            else { throw LibraryError.invalid("请先主动加入复习，再记录有效评分") }
            let existing = state.cards[index].schedule
            guard existing?.revision == expectedRevision else {
                throw LibraryError.invalid("卡片已在另一处复习，请重新打开")
            }
            if existing == nil && state.reviewRecords.contains(where: { $0.cardID == cardID }) {
                throw LibraryError.invalid("旧复习历史缺少调度状态，需先确认迁移，未重置历史")
            }
            var schedule = try existing ?? ReviewSchedule(now: now, retention: retention)
            try schedule.validate()
            let old = try JSONDecoder().decode(Card.self, from: schedule.engineState)
            if let last = old.lastReview, now < last { throw LibraryError.invalid("系统时间早于上次复习，未更新计划") }
            let params = try JSONDecoder().decode(FSRSParameters.self, from: schedule.parameters)
            let result = try FSRS(parameters: params).next(card: old, now: now, grade: grade)
            var record = LibraryReviewRecord(
                cardID: cardID, rating: rating, reviewedAt: now,
                elapsedMilliseconds: elapsedMilliseconds, schedulerVersion: schedule.version)
            record.id = eventID
            record.schedulerBefore = schedule.engineState
            record.schedulerAfter = try JSONEncoder().encode(result.card)
            record.schedulerLog = try JSONEncoder().encode(result.log)
            record.schedulerParameters = schedule.parameters
            schedule.engineState = try JSONEncoder().encode(result.card)
            schedule.due = result.card.due
            schedule.revision += 1
            state.cards[index].schedule = schedule
            state.reviewRecords.append(record)
        }
    }
}
