import SwiftUI
import YouTubePlayerKit

struct YouTubeStudyView: View {
    @StateObject private var model = YouTubeStudyModel()
    @State private var expanded = false
    @State private var preRoll = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("先捕捉，再整理").font(.title2.bold())
                    Text("YouTube 学习原型 · 标记保存在此设备，不自动建卡或加入复习。")
                        .foregroundStyle(.secondary)
                    if let error = model.storageError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                    HStack {
                        TextField("https://www.youtube.com/watch?v=…", text: $model.input)
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().keyboardType(.URL).onSubmit { model.openInput() }
                        Button("打开", action: model.openInput).buttonStyle(.borderedProminent)
                            .disabled(model.storageError != nil)
                    }
                    if let player = model.player {
                        // The wrapper binds its WKWebView at creation. A reconnect creates a new player.
                        YouTubePlayerView(player)
                            .id(ObjectIdentifier(player))
                            .frame(height: expanded ? 420 : 260)
                            .frame(maxWidth: .infinity)
                        Text(model.message).font(.callout).accessibilityIdentifier("playerStatus")
                        if let source = model.source {
                            Link("在 YouTube 打开", destination: source.videoID.watchURL)
                            Text("外部播放无法读取时间。Mark 不会获取字幕、音频或截图。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("开始一段学习", systemImage: "play.rectangle",
                                               description: Text(model.message))
                    }
                    if !expanded {
                        Divider()
                        HStack {
                            Text("时间标记").font(.headline)
                            Spacer()
                            Toggle("提前 3 秒回看", isOn: $preRoll).fixedSize()
                        }
                        if model.marks.isEmpty { Text("观看时点一下 Mark，无需填写表单。").foregroundStyle(.secondary) }
                        ForEach(model.marks) { mark in
                            HStack {
                                Image(systemName: "bookmark")
                                Text(String(format: "%.3f 秒", mark.seconds)).monospacedDigit()
                                Spacer()
                                Button("回看") { model.replay(mark, preRoll: preRoll) }
                                    .disabled(!model.isReady || model.isBusy)
                            }.padding(.vertical, 6)
                        }
                        if !model.sources.isEmpty {
                            Divider()
                            Text("最近学习").font(.headline)
                            ForEach(model.sources.reversed()) { source in
                                Button(source.videoID.rawValue) { model.activate(source.videoID) }
                            }
                        }
                    }
                }
                .padding(24).frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                if model.player != nil {
                    HStack(spacing: 16) {
                        Button(action: model.saveMark) { Label("Mark", systemImage: "bookmark.fill") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(!model.isReady || model.isBusy)
                        Button(expanded ? "收起" : "放大") { expanded.toggle() }
                        Spacer()
                        Button("重连") { if let source = model.source { model.activate(source.videoID) } }
                    }
                    .padding().background(.bar)
                }
            }
            .navigationTitle("Knowledge Studio")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
