import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var expandTokenEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.playback.track.title)
                    .font(.headline)
                Text(model.playback.track.artists)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("进度: \(model.playback.progressMs / 1000)s / \(model.playback.track.durationMs / 1000)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("当前歌词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.currentLine?.text ?? "尚未加载歌词")
                    .font(.body)
                if let subtext = model.currentLine?.subtext, !subtext.isEmpty {
                    Text(subtext)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("歌词来源：\(model.lyricsPayload?.source.displayName ?? "未加载")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("歌词源")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("歌词源", selection: $model.preferredChineseLyricsSource) {
                    Text("QQ 音乐").tag(LyricsSource.qqMusic)
                    Text("网易云").tag(LyricsSource.netease)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button(expandTokenEditor ? "收起 Spotify 凭据输入" : "填写 Spotify 凭据") {
                    expandTokenEditor.toggle()
                }

                if expandTokenEditor {
                    Text("Client ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("填写 Spotify Client ID", text: $model.spotifyClientID)
                        .textFieldStyle(.roundedBorder)

                    Text("Redirect URI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.spotifyRedirectURI)
                        .font(.caption)
                        .textSelection(.enabled)

                    Text("网页登录授权使用 PKCE，无需手动填写 Client Secret 或 Refresh Token。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button(model.isSpotifyAuthorizationInProgress ? "正在打开 Spotify 登录页…" : model.spotifyAuthorizationButtonTitle) {
                        model.authorizeSpotifyViaBrowser()
                    }
                    .disabled(model.isSpotifyAuthorizationInProgress)

                    if model.hasSpotifyRefreshToken {
                        Button("清除 Spotify 授权") {
                            model.clearSpotifyAuthorization()
                        }
                    }

                    Text("Spotify sp_dc（可选）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("可选：填写 sp_dc Cookie 值", text: $model.spotifySpDc)
                        .textFieldStyle(.roundedBorder)

                    Button("手动刷新访问令牌") {
                        model.refreshSpotifyAccessTokenManually()
                    }
                    .disabled(!model.hasSpotifyRefreshToken || model.isSpotifyAuthorizationInProgress)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("歌词岛显示模式")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("歌词岛显示模式", selection: $model.overlayDisplayMode) {
                    ForEach(OverlayDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("显示屏幕")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("显示屏幕", selection: $model.overlayScreenID) {
                    ForEach(model.overlayScreenOptions) { screen in
                        Text(screen.title).tag(screen.id)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("透明度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.overlayOpacityPercentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.overlayOpacity, in: 0.45...1.0, step: 0.01)

                HStack {
                    Text("大小")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.overlayScalePercentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.overlayScale, in: 0.8...1.3, step: 0.01)

                Text(model.overlayVisibilityStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button(model.overlayToggleButtonTitle) {
                    model.toggleOverlay()
                }

                Button("刷新 Spotify 播放状态") {
                    model.refreshPlayback()
                }
            }

            Divider()

            Text(model.spotifyTokenStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
    }
}
