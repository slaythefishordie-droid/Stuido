import SwiftUI

struct ExtensionSetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("compactDisplay") private var compactDisplay = false
    @AppStorage("appAppearance") private var appearance = "system"
    @AppStorage("pronunciationAccent") private var accent = "en-US"
    @State private var appRecord = "尚无记录"
    @State private var safariRecord = "尚无记录"
    @State private var status = "在 Safari 扩展菜单打开 Knowledge Studio，写入验证记录。"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("从 Safari 收集", systemImage: "safari")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("QuickMark 在原网页保存时间或段落，返回书房后可在收集箱整理。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.studyPanel()
                }.listRowBackground(Color.clear)
                Section("外观与发音") {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    Picker("发音口音偏好", selection: $accent) {
                        Text("美式英语").tag("en-US")
                        Text("英式英语").tag("en-GB")
                    }
                    Text(
                        "听发音会向维基词典查询所选单词，并缓存许可明确的录音；其他阅读内容不会发送。无法取得录音时使用设备语音，实际口音与来源会显示在播放入口。缓存由系统管理，不纳入知识库备份。"
                    ).font(.caption).foregroundStyle(.secondary)
                    Toggle("紧凑显示", isOn: $compactDisplay)
                    Text("Safari 面板可设置回溯、字号、控件位置和网站适配器。文章与播客按网站主动授权；停用后刷新网页生效。")
                }
                Section("Safari 扩展") {
                    Text("在 iPad 的 Safari 扩展设置中启用 Knowledge Studio。")
                    DisclosureGroup("共享诊断") {
                        Text("先在 Safari 写入记录，再分别核对两端编号。")
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent("主 App", value: appRecord).font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button("写入主 App 验证记录") { refresh(write: true) }
                        LabeledContent("Safari", value: safariRecord).font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button("重新读取共享记录") { refresh() }
                        Text(status).accessibilityIdentifier("extensionSharingStatus")
                        Text("编号一致后，重开 App 核对记录仍可读取。").font(.caption)
                    }
                }
            }.studySurface()
            .navigationTitle("设置")
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
