import SwiftUI

struct ExtensionSetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appRecord = "尚无记录"
    @State private var safariRecord = "尚无记录"
    @State private var status = "在 Safari 扩展菜单打开 Knowledge Studio，写入验证记录。"

    var body: some View {
        NavigationStack {
            Form {
                Section("Safari 扩展验证") {
                    Text("在 iPad 设置的 Safari 扩展列表启用 Knowledge Studio。然后在 Safari 页面菜单打开扩展。")
                    Text("先在 Safari 写入记录，再返回此页核对编号。随后在此写入记录，回到 Safari 读取并核对。")
                }
                Section("主 App 写入的记录") {
                    Text(appRecord).font(.footnote.monospaced()).textSelection(.enabled)
                    Button("写入主 App 验证记录") { refresh(write: true) }
                }
                Section("Safari 写入的记录") {
                    Text(safariRecord).font(.footnote.monospaced()).textSelection(.enabled)
                    Button("重新读取共享记录") { refresh() }
                }
                Section("状态") {
                    Text(status).accessibilityIdentifier("extensionSharingStatus")
                    Text("两端显示相同编号后，请再关闭并重新打开主 App，确认记录仍可读取。")
                }
            }
            .navigationTitle("Safari 扩展")
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh(write: Bool = false) {
        do {
            let store = try SharedProbeStore.configured()
            if write { _ = try store.write(from: .app) }
            appRecord = try store.read(from: .app)?.id.uuidString ?? "尚无记录"
            safariRecord = try store.read(from: .safari)?.id.uuidString ?? "尚无记录"
            status = "共享目录可访问。请在两端核对记录编号。"
        } catch {
            appRecord = "读取未完成"
            safariRecord = "读取未完成"
            status = error.localizedDescription
        }
    }
}
