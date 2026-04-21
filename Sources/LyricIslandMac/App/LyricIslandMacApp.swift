import SwiftUI

@main
struct LyricIslandMacApp: App {
    private let model: AppModel

    init() {
        model = AppModel()
        model.start()
    }

    var body: some Scene {
        MenuBarExtra("歌词岛", systemImage: "music.note") {
            MenuBarView(model: model)
                .frame(width: 340)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(width: 560)
        }
    }
}
