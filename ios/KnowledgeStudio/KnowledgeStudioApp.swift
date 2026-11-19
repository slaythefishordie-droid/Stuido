import SwiftUI

@main
struct KnowledgeStudioApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                MyInboxView().tabItem { Label("My Inbox", systemImage: "tray") }
                ExtensionSetupView().tabItem { Label("扩展设置", systemImage: "puzzlepiece.extension") }
            }
        }
    }
}
