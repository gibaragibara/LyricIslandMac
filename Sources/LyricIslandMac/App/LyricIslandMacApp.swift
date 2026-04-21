import SwiftUI

@main
struct LyricIslandMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("歌词岛", systemImage: "music.note") {
            MenuBarView(model: model)
                .frame(width: 340)
                .onAppear {
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(width: 560)
        }
    }
}
