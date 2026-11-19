import KnowledgeCore
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response: [String: Any]
        do {
            guard let item = context.inputItems.first as? NSExtensionItem,
                let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
                let action = message["action"] as? String,
                ["readProbe", "writeProbe", "saveMark", "listMarks", "annotateMark", "savePageMark"].contains(
                    action)
            else {
                throw NSError(
                    domain: "SharedProbe", code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey: "不支持的扩展请求。"
                    ])
            }
            if action == "savePageMark" {
                guard let payload = message["mark"], JSONSerialization.isValidJSONObject(payload) else {
                    throw VideoError.corruptStore
                }
                let data = try JSONSerialization.data(withJSONObject: payload)
                guard data.count <= 65_536 else { throw VideoError.corruptStore }
                let capture = try JSONDecoder().decode(PageCapture.self, from: data)
                try PageCaptureStore.configured().save(capture)
                response = ["ok": true, "id": capture.id.uuidString.lowercased()]
            } else if action == "listMarks" {
                let marks = try WebMarkStore.configured().readAll()
                response = [
                    "ok": true, "marks": try JSONSerialization.jsonObject(with: JSONEncoder().encode(marks)),
                ]
            } else if action == "annotateMark" {
                guard let value = message["id"] as? String, let id = UUID(uuidString: value) else {
                    throw VideoError.corruptStore
                }
                try WebMarkStore.configured().annotate(
                    id: id, note: message["note"] as? String, deleted: message["deleted"] as? Bool)
                response = ["ok": true, "id": id.uuidString.lowercased()]
            } else if action == "saveMark" {
                guard let payload = message["mark"], JSONSerialization.isValidJSONObject(payload) else {
                    throw VideoError.corruptStore
                }
                let data = try JSONSerialization.data(withJSONObject: payload)
                guard data.count <= 16_384 else { throw VideoError.corruptStore }
                let mark = try JSONDecoder().decode(WebMark.self, from: data)
                try WebMarkStore.configured().save(mark)
                response = ["ok": true, "id": mark.id.uuidString.lowercased()]
            } else {
                let store = try SharedProbeStore.configured()
                if action == "writeProbe" { _ = try store.write(from: .safari) }
                response = [
                    "ok": true,
                    "app": try store.read(from: .app)?.id.uuidString ?? "尚无记录",
                    "safari": try store.read(from: .safari)?.id.uuidString ?? "尚无记录",
                ]
            }
        } catch {
            response = ["ok": false, "error": error.localizedDescription]
        }
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
