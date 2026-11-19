import Foundation
import KnowledgeCore

extension WebMarkStore {
    static func configured() throws -> WebMarkStore {
        let group = try SharedProbeStore.groupIdentifier(in: Bundle.main.infoDictionary ?? [:])
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw SharedProbeStore.StoreError.unavailableGroup(group)
        }
        return WebMarkStore(directory: container.appendingPathComponent("WebMarks-v1"))
    }
}
