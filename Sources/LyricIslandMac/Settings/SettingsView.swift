import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Spotify 配置") {
                Text("Client ID")
                    .font(.headline)
                TextField("填写 Spotify Client ID", text: $model.spotifyClientID)
                    .textFieldStyle(.roundedBorder)

                Text("Redirect URI")
                    .font(.headline)
                Text(model.spotifyRedirectURI)
                    .textSelection(.enabled)

                Text("请先在 Spotify Developer Dashboard 的 Redirect URI 中添加上面的地址，然后再进行网页登录授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("授权范围：\(model.spotifyScopeSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("打开 Spotify Developer Dashboard") {
                        model.openSpotifyDeveloperDashboard()
                    }

                    Button(model.isSpotifyAuthorizationInProgress ? "正在打开 Spotify 登录页…" : model.spotifyAuthorizationButtonTitle) {
                        model.authorizeSpotifyViaBrowser()
                    }
                    .disabled(model.isSpotifyAuthorizationInProgress)
                }

                if model.hasSpotifyRefreshToken {
                    Button("清除 Spotify 授权") {
                        model.clearSpotifyAuthorization()
                    }
                }

                Text("Spotify sp_dc（可选，用于 helper 侧 Spotify 歌词/搜索）")
                    .font(.headline)
                SecureField("填写 sp_dc Cookie 值", text: $model.spotifySpDc)
                    .textFieldStyle(.roundedBorder)

                Button("手动刷新访问令牌") {
                    model.refreshSpotifyAccessTokenManually()
                }
                .disabled(!model.hasSpotifyRefreshToken || model.isSpotifyAuthorizationInProgress)

                Text(model.spotifyTokenStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("歌词服务") {
                Text("歌词服务可执行路径")
                    .font(.headline)
                TextField("LyricIsland.LyricsService 的路径", text: $model.helperExecutablePath)
                    .textFieldStyle(.roundedBorder)
                Text("Swift 只负责 macOS 原生壳层。歌词由本地 .NET helper 进程处理，并接入 Lyricify-Lyrics-Helper。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("歌词岛外观") {
                HStack {
                    Text("透明度")
                    Spacer()
                    Text(model.overlayOpacityPercentText)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.overlayOpacity, in: 0.45...1.0, step: 0.01)

                HStack {
                    Text("大小")
                    Spacer()
                    Text(model.overlayScalePercentText)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.overlayScale, in: 0.8...1.3, step: 0.01)
            }

            Section("范围") {
                Text("播放源：Spotify")
                Text("歌词源：Spotify / QQ 音乐 / 网易云")
            }
        }
        .padding(16)
    }
}
