import KnowledgeCore
import SwiftUI

/// A view onto the existing library, not a second store or a new scheduling system.
struct StudyHomeView: View {
    @EnvironmentObject private var model: StudioModel
    private var reading: [LibrarySource] {
        model.state.sources.filter { $0.deletedAt == nil && $0.lastLocation != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("留一点时间，读下去。").font(.title2).fontDesign(.serif)
                        Text("从上次的位置继续，或打开一个研究项目。").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                Section {
                    NavigationLink {
                        TodayView()
                    } label: {
                        Label("今日复习", systemImage: "calendar")
                    }
                }
                Section("继续阅读") {
                    if reading.isEmpty {
                        Text("在资料库打开一本书，阅读位置会保留在这里。").foregroundStyle(.secondary)
                    }
                    ForEach(Array(reading.prefix(6))) { source in
                        NavigationLink {
                            SourceReaderView(source: source, location: source.lastLocation)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.title).font(.headline)
                                    Text(source.lastLocation.map(locationLabel) ?? "继续阅读").font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "book")
                            }
                        }
                    }
                }
                Section("研究项目") {
                    ForEach(model.state.projects.filter { $0.deletedAt == nil }) { project in
                        NavigationLink {
                            ProjectView(projectID: project.id)
                        } label: {
                            Label(project.title, systemImage: "folder")
                        }
                    }
                }
                Section("最近更新的知识") {
                    ForEach(
                        Array(
                            model.state.cards.filter { $0.deletedAt == nil }.sorted {
                                $0.updatedAt > $1.updatedAt
                            }.prefix(8))
                    ) { card in
                        NavigationLink {
                            CardDetailView(cardID: card.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.title).lineLimit(3)
                                Text(card.type.title).font(.caption).foregroundStyle(card.type.color)
                            }
                        }
                    }
                }
            }.navigationTitle("书桌")
        }
    }
}
