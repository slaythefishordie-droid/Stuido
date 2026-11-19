import SwiftUI
import KnowledgeCore

struct MyInboxView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var marks: [WebMark] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if marks.isEmpty {
                    Text("在 Safari 的 YouTube 视频页面点击 QuickMark，返回这里查看。标记不会自动建卡或加入复习。")
                }
                ForEach(marks) { mark in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mark.title).font(.headline)
                        Text("\(Int(mark.seconds)) 秒 · \(Date(timeIntervalSince1970: mark.createdAt / 1000).formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("回到出处", destination: URL(string: mark.sourceURL.absoluteString + "&t=\(Int(mark.seconds))s")!)
                        Text(mark.id.uuidString).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("My Inbox")
            .toolbar { Button("刷新", action: refresh) }
            .refreshable { refresh() }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        do {
            marks = try WebMarkStore.configured().readAll()
            error = nil
        } catch { self.error = "读取未完成，原记录已保留：\(error.localizedDescription)" }
    }
}
