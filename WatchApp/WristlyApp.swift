import SwiftUI

@main
struct WristlyApp: App {
    @StateObject private var settings = SettingsStore()
    var body: some Scene {
        WindowGroup { NavigationStack { ChatView() }.environmentObject(settings) }
    }
}
