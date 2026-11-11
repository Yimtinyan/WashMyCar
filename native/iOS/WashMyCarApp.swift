import SwiftUI
import AppIntents

@main
struct WashMyCarApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Style.green)
                .preferredColorScheme(store.state["settings"]["theme"].text == "dark" ? .dark : store.state["settings"]["theme"].text == "light" ? .light : nil)
                .onChange(of: phase) { _, next in if next == .active { store.connection.checkConnection() } }
        }
    }
}

struct OpenWashIntent: AppIntent {
    static var title: LocalizedStringResource = "打开洗车流程"
    static var description = IntentDescription("打开 WashMyCar，查看或继续洗车。不会扣库存或自动结束步骤。")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { .result() }
}
struct WashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenWashIntent(), phrases: ["用\(.applicationName)洗车"], shortTitle: "打开洗车流程", systemImageName: "car.side")
    }
}
