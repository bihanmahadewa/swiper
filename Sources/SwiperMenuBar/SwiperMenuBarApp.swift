import SwiftUI
@main
struct SwiperMenuBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
                .frame(width: 320)
        } label: {
            Label(appState.menuBarTitle(), systemImage: appState.trackerStatus?.state == "watching" ? "record.circle.fill" : "pause.circle")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Swiper") {
                    appState.handleAppTermination()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
