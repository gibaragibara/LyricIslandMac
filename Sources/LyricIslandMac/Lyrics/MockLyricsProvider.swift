import Foundation

enum MockLyricsProvider {
    static func makeDemoLyrics(for track: TrackInfo, source: LyricsSource) -> LyricsPayload {
        LyricsPayload(
            source: source,
            track: track,
            lines: [
                .init(text: "歌词岛已启动，正在同步状态", subtext: nil, startTimeMs: 0, endTimeMs: 5_000),
                .init(text: "Spotify 负责播放进度与歌曲信息", subtext: nil, startTimeMs: 5_000, endTimeMs: 10_000),
                .init(text: "歌词链路已接入本地 .NET 服务", subtext: nil, startTimeMs: 10_000, endTimeMs: 15_000),
                .init(text: "已支持 Spotify、QQ 音乐、网易云来源", subtext: nil, startTimeMs: 15_000, endTimeMs: 22_000),
                .init(text: "刘海区域歌词会随时间轴滚动更新", subtext: nil, startTimeMs: 22_000, endTimeMs: 29_000),
            ]
        )
    }
}
