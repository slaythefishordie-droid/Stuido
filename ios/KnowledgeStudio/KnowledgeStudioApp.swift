import SwiftUI

@main
struct KnowledgeStudioApp: App {
    @UIApplicationDelegateAdaptor(LoungeAppDelegate.self) private var loungeDelegate
    var body: some Scene { WindowGroup { StudioView() } }
}
