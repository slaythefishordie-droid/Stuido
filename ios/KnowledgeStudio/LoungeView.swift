import Charts
import KnowledgeCore
import SwiftUI
import UniformTypeIdentifiers

struct LoungeView: View {
    @EnvironmentObject private var hub: LoungeHub
    @Environment(StudioModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var music = false
    @State private var schedule = false
    @State private var prompts: LoungePromptKind?
    @State private var stats = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    if geometry.size.width >= 750 {
                        HStack(alignment: .top, spacing: 19) {
                            musicCorner.frame(maxWidth: .infinity)
                            VStack(spacing: 16) { promptCard(.activity); promptCard(.trivia) }
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        musicCorner
                        promptCard(.activity)
                        promptCard(.trivia)
                    }
                    timeShelf
                }.padding(24).frame(maxWidth: 1060).frame(maxWidth: .infinity)
            }
        }.studySurface()
            .sheet(isPresented: $music) {
                LoungeMusicLibrary().environmentObject(hub).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $schedule) { LoungeTimerPanel().environmentObject(hub) }
            .sheet(isPresented: $stats) {
                NavigationStack { LoungeStatsView().environmentObject(hub).environment(model) }
            }
            .sheet(item: $prompts) { LoungePromptLibrary(kind: $0).environmentObject(hub) }
    }

    private var heading: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text("休息室").font(.system(.largeTitle, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { schedule = true } label: {
                LoungeActivityTimeline(active: hub.countdown.deadline != nil) { context in
                    Label(hub.countdown.isStarted ? loungeClock(hub.countdown.remaining(at: context)) : "设定计时",
                        systemImage: "timer")
                        .monospacedDigit()
                }
            }.buttonStyle(.bordered)
        }
    }

    private var musicCorner: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StudyHeading(title: "音乐角落")
                Spacer()
                Button("曲库", systemImage: "music.note.list") { music = true }.font(.subheadline)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(StudyTheme.plum)
                Circle().fill(.black.opacity(0.82)).padding(17).offset(x: 23)
                ForEach(0..<7) { groove in
                    Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        .padding(CGFloat(23 + groove * 8)).offset(x: 23)
                }
                if let data = hub.track?.artwork, let cover = UIImage(data: data) {
                    Image(uiImage: cover).resizable().scaledToFill().frame(width: 105, height: 105)
                        .clipped().offset(x: -48)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "music.quarternote.3").font(.largeTitle)
                        RoundedRectangle(cornerRadius: 1).frame(width: 33, height: 1)
                    }.foregroundStyle(StudyTheme.plum).frame(width: 105, height: 105)
                        .background(Color(uiColor: StudyTheme.rgb(0xDDB691))).rotationEffect(.degrees(-5)).offset(x: -48)
                }
            }.frame(height: 188).clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(hub.track?.title ?? "唱片架").font(.system(.title2, design: .serif))
                if let track = hub.track, ![track.artist, track.album].allSatisfy(\.isEmpty) {
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.contentTransition(.opacity).animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hub.track?.id)
            LoungeTransport(full: true)
            if hub.tracks.isEmpty {
                Button("导入音乐", systemImage: "square.and.arrow.down") { music = true }.buttonStyle(.bordered)
            }
        }.studyPanel()
    }

    private func promptCard(_ kind: LoungePromptKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: kind == .activity ? "sparkle" : "book.closed")
                    .foregroundStyle(StudyTheme.copper)
                Text(kind.title).font(.system(.title3, design: .serif)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { prompts = kind } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("打开\(kind.title)清单")
            }
            if let prompt = hub.recent(kind).first {
                VStack(alignment: .leading, spacing: 7) {
                    if !prompt.title.isEmpty { Text(prompt.title).font(.headline) }
                    Text(prompt.text).font(.system(.body, design: .serif)).lineLimit(4)
                }.id(prompt.id).transition(.opacity)
                HStack {
                    Button { hub.favorite(prompt) } label: {
                        Image(systemName: prompt.favorite ? "heart.fill" : "heart")
                    }.accessibilityLabel(prompt.favorite ? "取消收藏" : "收藏")
                    Spacer()
                    if let source = prompt.source { Link("来源", destination: source).font(.caption) }
                    Button("换一张", systemImage: "arrow.clockwise") { hub.draw(kind) }.font(.caption)
                }
            } else {
                Button("打开清单", systemImage: "plus") { prompts = kind }.font(.subheadline)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(kind == .activity ? StudyTheme.leaf : StudyTheme.mat)
            .overlay(alignment: .leading) { Rectangle().fill(StudyTheme.copper.opacity(0.65)).frame(width: 2) }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hub.recent(kind).first?.id)
    }

    private var timeShelf: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let day = Calendar.current.dateInterval(of: .day, for: context.date)
            let duration = day.map { interval in
                hub.intervals(at: context.date).reduce(0) { $0 + $1.seconds(in: interval) }
            } ?? 0
            Button { stats = true } label: {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "sun.horizon").font(.title2).foregroundStyle(StudyTheme.copper)
                    VStack(alignment: .leading, spacing: 3) {
                        StudyHeading(title: "学习时光")
                        Text("今日 · " + loungeDuration(duration)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading).studyPanel()
            }.buttonStyle(.plain)
        }
    }
}

private func loungeClock(_ seconds: TimeInterval) -> String {
    let value = Int(ceil(max(0, seconds)))
    if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
    return String(format: "%02d:%02d", value / 60, value % 60)
}

private func loungeDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(max(0, seconds) / 60)
    if minutes == 0 { return "\(Int(max(0, seconds))) 秒" }
    if minutes < 60 { return "\(minutes) 分钟" }
    return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
}

struct LoungeTransport: View {
    @EnvironmentObject private var hub: LoungeHub
    var full = false
    @State private var scrubbing = false
    @State private var seek = 0.0
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 16) {
                Button { hub.skip(-1) } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("上一首").disabled(hub.tracks.isEmpty)
                Button { hub.togglePlayback() } label: {
                    Image(systemName: hub.playing ? "pause.fill" : "play.fill").frame(minWidth: 30)
                }.accessibilityLabel(hub.playing ? "暂停" : "播放").disabled(hub.tracks.isEmpty)
                Button { hub.skip(1) } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel("下一首").disabled(hub.tracks.isEmpty)
                if full {
                    Spacer()
                    Picker("播放模式", selection: $hub.mode) {
                        ForEach(LoungeHub.PlaybackMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                }
            }.buttonStyle(.borderless)
            if full, let track = hub.track {
                LoungeActivityTimeline(active: hub.playing) { _ in
                    Slider(value: Binding(get: { scrubbing ? seek : min(track.duration, hub.playhead) }, set: { seek = $0 }),
                        in: 0...max(1, track.duration), onEditingChanged: { editing in
                            if editing { seek = hub.playhead; scrubbing = true }
                            else { hub.seek(seek); scrubbing = false }
                        }).accessibilityLabel("播放进度")
                    HStack {
                        Text(loungeClock(scrubbing ? seek : hub.playhead))
                        Spacer()
                        Text(loungeClock(track.duration))
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $hub.volume, in: 0...1).accessibilityLabel("音量")
                }.font(.caption)
            }
        }
    }
}

private struct LoungeTimerPanel: View {
    @EnvironmentObject private var hub: LoungeHub
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    LoungeInlineFeedback()
                    LoungeActivityTimeline(active: hub.countdown.deadline != nil) { context in
                        Text(hub.countdown.isStarted ? loungeClock(hub.countdown.remaining(at: context))
                            : loungeClock(Double(minutes * 60)))
                            .font(.system(size: 52, weight: .medium, design: .serif)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if hub.countdown.isStarted {
                        HStack {
                            if hub.countdown.deadline != nil { Button("暂停") { hub.pauseTimer() } }
                            else { Button("继续") { hub.resumeTimer() } }
                            Button("取消计时", role: .destructive) { hub.cancelTimer() }
                        }.buttonStyle(.bordered)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))]) {
                            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { value in
                                Button("\(value) 分") { minutes = value }
                                    .buttonStyle(.bordered).tint(minutes == value ? StudyTheme.ink : .secondary)
                            }
                        }
                        Stepper("自定 · \(minutes) 分钟", value: $minutes, in: 15...120, step: 5)
                        Button("开始计时", systemImage: "timer") { hub.startTimer(minutes) }.buttonStyle(.borderedProminent)
                    }
                }.studyPanel().padding(20)
            }.studySurface().navigationTitle("专注与休息").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完成") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}

private struct LoungeStatsView: View {
    @EnvironmentObject private var hub: LoungeHub
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var days = 7
    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { clock in
            let calendar = Calendar.current
            let records = hub.intervals(at: clock.date)
            let start = calendar.startOfDay(for: clock.date)
            let trend = (0..<days).reversed().compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: start)
                    .flatMap { calendar.dateInterval(of: .day, for: $0) }
            }.map { day in
                Day(date: day.start, duration: records.reduce(0) { $0 + $1.seconds(in: day) })
            }
            let today = calendar.dateInterval(of: .day, for: start)
            let relevant = records.filter { record in today.map { record.seconds(in: $0) > 0 } ?? false }
            let total = trend.last?.duration ?? 0
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        StudyHeading(title: "今日 · " + loungeDuration(total))
                        Picker("趋势", selection: $days) {
                            Text("一周").tag(7); Text("一月").tag(30)
                        }.pickerStyle(.segmented)
                        Chart(trend) { day in
                            BarMark(x: .value("日期", day.date, unit: .day),
                                y: .value("分钟", day.duration / 60))
                                .foregroundStyle(StudyTheme.copper)
                        }.frame(height: 135).accessibilityLabel("每日学习分钟数")
                    }.studyPanel()
                }.listRowBackground(Color.clear)
                Section("今日资料分布") {
                    let grouped = Dictionary(grouping: relevant, by: \.sourceID).map { id, intervals in
                        SourceTime(id: id, title: sourceName(id), seconds: intervals.reduce(0) { total, record in
                            total + (today.map { record.seconds(in: $0) } ?? 0)
                        })
                    }.sorted { $0.seconds > $1.seconds }
                    if grouped.isEmpty { Text("今天还没有记录").foregroundStyle(.secondary) }
                    ForEach(grouped) { source in
                        LabeledContent(source.title, value: loungeDuration(source.seconds))
                    }
                }
                Section("今日时间轴") {
                    ForEach(relevant.reversed()) { record in
                        LabeledContent {
                            Text(loungeDuration(today.map(record.seconds(in:)) ?? 0))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(sourceName(record.sourceID))
                                Text(max(start, record.start), style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("每日历史") {
                    LabeledContent("累计使用", value: loungeDuration(records.reduce(0) { $0 + $1.duration }))
                    let history = historyDays(records, calendar: calendar)
                    ForEach(history) { item in
                        LabeledContent(item.date.formatted(date: .abbreviated, time: .omitted),
                            value: loungeDuration(item.duration))
                    }
                }
            }.studySurface()
        }.navigationTitle("学习时光").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
    }

    private struct Day: Identifiable { var id: Date { date }; let date: Date; let duration: TimeInterval }
    private struct SourceTime: Identifiable { let id: UUID?; let title: String; let seconds: TimeInterval }
    private func sourceName(_ id: UUID?) -> String {
        guard let id else { return "书房其他活动" }
        return model.sources.first { $0.id == id }?.title ?? "已移除的资料"
    }
    private func historyDays(_ records: [StudyInterval], calendar: Calendar) -> [Day] {
        var totals: [Date: TimeInterval] = [:]
        for record in records {
            var cursor = record.start
            while cursor < record.end, let day = calendar.dateInterval(of: .day, for: cursor) {
                totals[day.start, default: 0] += record.seconds(in: day)
                cursor = day.end
            }
        }
        return totals.keys.sorted(by: >).map { Day(date: $0, duration: totals[$0] ?? 0) }
    }
}

private struct LoungeMusicLibrary: View {
    @EnvironmentObject private var hub: LoungeHub
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var favorites = false
    @State private var sort = "标题"
    @State private var playlist: UUID?
    @State private var newList = false
    @State private var name = ""
    @State private var removeTrack: LoungeTrack?
    @State private var search = ""

    private var selection: LoungePlaylist? { hub.playlists.first { $0.id == playlist } }
    private var tracks: [LoungeTrack] {
        let list = selection
        let items = hub.tracks.filter {
            (!favorites || $0.favorite) && (list?.trackIDs.contains($0.id) ?? true) &&
                (search.isEmpty || [$0.title, $0.artist, $0.album].contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return items.sorted {
            if sort == "专辑", $0.album != $1.album { return $0.album.localizedStandardCompare($1.album) == .orderedAscending }
            if sort == "艺人", $0.artist != $1.artist { return $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                LoungeInlineFeedback()
                if hub.importing { ProgressView("正在复制与检查音频…") }
                Picker("播放列表", selection: $playlist) {
                    Text("全部曲目").tag(nil as UUID?)
                    ForEach(hub.playlists) { Text($0.name).tag(Optional($0.id)) }
                }
                HStack {
                    Toggle("仅收藏", isOn: $favorites)
                    Spacer()
                    Picker("排序", selection: $sort) {
                        ForEach(["标题", "专辑", "艺人"], id: \.self) { Text($0) }
                    }.pickerStyle(.menu)
                }
                if tracks.isEmpty {
                    ContentUnavailableView("没有曲目", systemImage: "music.note.list")
                }
                ForEach(tracks) { track in
                    HStack {
                        Button { hub.play(track, scope: playlist) } label: {
                            HStack {
                                Image(systemName: hub.track?.id == track.id && hub.playing ? "waveform" : "music.note")
                                    .frame(width: 27)
                                VStack(alignment: .leading) {
                                    Text(track.title).font(.headline)
                                    let subtitle = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(loungeClock(track.duration)).font(.caption.monospacedDigit())
                            }.contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                        Menu {
                            Button(track.favorite ? "取消收藏" : "收藏") { hub.favorite(track) }
                            ForEach(hub.playlists) { list in
                                let included = list.trackIDs.contains(track.id)
                                Button((included ? "移出 " : "加入 ") + list.name) {
                                    hub.assign(track, to: list, remove: included)
                                }
                            }
                            Button("移除曲目", role: .destructive) { removeTrack = track }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("曲目操作")
                    }
                }
            }.studySurface().navigationTitle("个人曲库").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: "搜索曲目")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("从文件导入", systemImage: "square.and.arrow.down") { importing = true }
                                .disabled(hub.importing)
                            Button("新建播放列表", systemImage: "plus") { name = ""; newList = true }
                            if let list = selection {
                                Button("移除播放列表", role: .destructive) { hub.remove(list); playlist = nil }
                            }
                        } label: { Label("曲库操作", systemImage: "plus") }
                    }
                }
        }.fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            Task {
                do { await hub.importTracks(try result.get()) }
                catch { hub.message = error.localizedDescription }
            }
        }.alert("新建播放列表", isPresented: $newList) {
            TextField("名称", text: $name)
            Button("创建") { hub.makePlaylist(name) }
            Button("取消", role: .cancel) {}
        }.confirmationDialog("从曲库移除这首歌？", isPresented: Binding(get: { removeTrack != nil }, set: {
            if !$0 { removeTrack = nil }
        }), titleVisibility: .visible, presenting: removeTrack) { track in
            Button("移除", role: .destructive) { hub.remove(track) }
        }
    }
}

private struct LoungePromptLibrary: View {
    @EnvironmentObject private var hub: LoungeHub
    @Environment(\.dismiss) private var dismiss
    let kind: LoungePromptKind
    @State private var importing = false
    @State private var busy = false
    @State private var edit: LoungePrompt?
    @State private var pane = "清单"
    @State private var wikiQuery = ""
    @State private var wiki: WikipediaNote?
    @State private var wikiError: String?
    @State private var lookingUp = false

    var body: some View {
        NavigationStack {
            List {
                LoungeInlineFeedback()
                Picker("浏览", selection: $pane) {
                    ForEach(["清单", "收藏", "最近"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                if kind == .trivia { wikipedia }
                if busy { ProgressView("正在读取清单…") }
                if entries.isEmpty { ContentUnavailableView("暂无内容", systemImage: "note.text") }
                ForEach(entries) { entry in
                    HStack {
                        Button { edit = entry } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if !entry.title.isEmpty { Text(entry.title).font(.headline) }
                                Text(entry.text).lineLimit(3)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                        Button { hub.favorite(entry) } label: { Image(systemName: entry.favorite ? "heart.fill" : "heart") }
                            .buttonStyle(.borderless).accessibilityLabel(entry.favorite ? "取消收藏" : "收藏")
                    }.swipeActions {
                        Button("删除", role: .destructive) { hub.remove(entry) }
                    }
                }
            }.studySurface().navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("导入 TXT 或 CSV") { importing = true }.disabled(busy)
                            Button("添加一条") { edit = LoungePrompt(kind: kind, title: "", text: "") }
                            Button("随机换一张") { hub.draw(kind) }.disabled(hub.prompts(kind).isEmpty)
                        } label: { Label("清单操作", systemImage: "plus") }
                    }
                }
        }.fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText]) { result in
            busy = true
            Task {
                defer { busy = false }
                do { await hub.importPrompts(try result.get(), kind: kind) }
                catch { hub.message = error.localizedDescription }
            }
        }.sheet(item: $edit) { LoungePromptEditor(prompt: $0).environmentObject(hub) }
    }

    private var entries: [LoungePrompt] {
        if pane == "最近" {
            var seen: Set<UUID> = []
            return hub.recent(kind).filter { seen.insert($0.id).inserted }
        }
        return hub.prompts(kind).filter { pane != "收藏" || $0.favorite }
    }

    private var wikipedia: some View {
        Section("百科补充") {
            HStack {
                TextField("查询主题", text: $wikiQuery)
                Button("查询") {
                    let term = wikiQuery
                    lookingUp = true
                    wikiError = nil
                    wiki = nil
                    Task {
                        defer { lookingUp = false }
                        do { wiki = try await hub.lookup(term) }
                        catch { wikiError = "暂时无法查询百科。你的清单可以离线使用。" }
                    }
                }.disabled(lookingUp || wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if lookingUp { ProgressView() }
            if let wikiError { Text(wikiError).font(.caption).foregroundStyle(.secondary) }
            if let wiki {
                DisclosureGroup(wiki.title) {
                    Text(wiki.extract).font(.callout)
                    Link("Wikipedia · 原文与 CC BY-SA 署名", destination: wiki.url).font(.caption)
                }
            }
        }
    }
}

private struct LoungePromptEditor: View {
    @EnvironmentObject private var hub: LoungeHub
    @Environment(\.dismiss) private var dismiss
    @State var prompt: LoungePrompt
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题（选填）", text: $prompt.title)
                TextField("内容", text: $prompt.text, axis: .vertical).lineLimit(3...8)
                if prompt.kind == .trivia {
                    TextField("HTTPS 来源（选填）", text: $link).textInputAutocapitalization(.never).keyboardType(.URL)
                }
            }.studySurface().navigationTitle("编辑纸条").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            prompt.source = URL(string: link).flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
                            hub.save(prompt)
                            if hub.recent(prompt.kind).isEmpty { hub.draw(prompt.kind) }
                            dismiss()
                        }.disabled(prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.onAppear { link = prompt.source?.absoluteString ?? "" }
    }
}

private struct LoungeInlineFeedback: View {
    @EnvironmentObject private var hub: LoungeHub
    var body: some View {
        if let message = hub.message {
            HStack {
                Text(message).font(.callout)
                Spacer()
                Button("关闭") { hub.message = nil }.buttonStyle(.borderless)
            }.foregroundStyle(StudyTheme.ink)
        }
    }
}

struct LoungePreferences: View {
    @EnvironmentObject private var hub: LoungeHub
    @AppStorage("loungeTimerPopup") private var popup = true
    @AppStorage("loungeTimerSilent") private var silent = false
    @AppStorage("loungeTimerHaptics") private var haptics = false
    @AppStorage("loungePopupSeconds") private var popupSeconds = 12
    @AppStorage("loungeDrawInterval") private var drawInterval = 30

    var body: some View {
        StudyPreferenceShelf("计时提醒") {
            Toggle("右下角浮窗", isOn: $popup)
            Toggle("静默提醒", isOn: $silent).onChange(of: silent) { _, _ in hub.reminderPreferencesChanged() }
            Toggle("触觉反馈（设备支持时）", isOn: $haptics)
            Stepper("浮窗显示 \(popupSeconds) 秒", value: $popupSeconds, in: 5...30)
                .disabled(!popup)
        }
        StudyPreferenceShelf("休息纸条") {
            Picker("自动更新", selection: $drawInterval) {
                Text("仅手动").tag(0)
                ForEach([5, 15, 30, 60, 120], id: \.self) { Text("\($0) 分钟").tag($0) }
            }.onChange(of: drawInterval) { _, _ in hub.refreshRecommendationSchedule() }
        }
    }
}

/// A paused clock/audio transport has no time-driven display work. Scene changes
/// restore the real current date immediately; reminder scheduling stays in the hub.
private struct LoungeActivityTimeline<Content: View>: View {
    @Environment(\.scenePhase) private var phase
    let active: Bool
    @ViewBuilder var content: (Date) -> Content
    var body: some View {
        if active && phase == .active {
            TimelineView(.periodic(from: .now, by: 1)) { context in content(context.date) }
        } else {
            content(.now)
        }
    }
}
