import Foundation

enum LyricsSource: String, Codable, CaseIterable {
    case spotify = "spotify"
    case qqMusic = "qq_music"
    case netease = "netease"

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .qqMusic: return "QQ 音乐"
        case .netease: return "网易云"
        }
    }
}

struct TrackInfo: Codable, Equatable {
    var id: String
    var title: String
    var artists: String
    var album: String
    var durationMs: Int
    var artistArtworkURL: String? = nil
    var artworkURL: String? = nil

    var displayTitle: String {
        "\(title) - \(artists)"
    }
}

struct PlaybackSnapshot: Equatable {
    var track: TrackInfo
    var progressMs: Int
    var isPlaying: Bool

    static let demo = PlaybackSnapshot(
        track: TrackInfo(
            id: "spotify:track:demo",
            title: "示例歌曲",
            artists: "示例歌手",
            album: "示例专辑",
            durationMs: 210_000,
            artworkURL: nil
        ),
        progressMs: 0,
        isPlaying: true
    )
}

struct LyricLine: Codable, Equatable {
    var text: String
    var subtext: String?
    var startTimeMs: Int
    var endTimeMs: Int?
    var syllables: [LyricSyllable]? = nil
}

struct LyricSyllable: Codable, Equatable {
    var text: String
    var startTimeMs: Int
    var endTimeMs: Int
}

struct LyricsPayload: Codable, Equatable {
    var source: LyricsSource
    var track: TrackInfo
    var lines: [LyricLine]
}

extension Array where Element == LyricLine {
    func linePair(at progressMs: Int) -> (current: LyricLine?, next: LyricLine?) {
        guard !isEmpty else {
            return (nil, nil)
        }

        let ordered = sorted { $0.startTimeMs < $1.startTimeMs }
        var current: LyricLine?
        var next: LyricLine?

        for (index, line) in ordered.enumerated() {
            let lineEnd = line.endTimeMs ?? Int.max
            if progressMs >= line.startTimeMs && progressMs < lineEnd {
                current = line
                next = index + 1 < ordered.count ? ordered[index + 1] : nil
                break
            }
            if progressMs < line.startTimeMs {
                current = nil
                next = line
                break
            }
        }

        if current == nil && next == nil {
            current = ordered.last
        }

        return (current, next)
    }
}

extension LyricLine {
    func karaokeProgress(at progressMs: Int) -> Double {
        if let syllables, !syllables.isEmpty {
            let totalWeight = Double(syllables.reduce(0) { partial, syllable in
                partial + max(1, syllable.text.count)
            })
            guard totalWeight > 0 else {
                return 0
            }

            var highlightedWeight = 0.0
            for syllable in syllables {
                let weight = Double(max(1, syllable.text.count))
                if progressMs >= syllable.endTimeMs {
                    highlightedWeight += weight
                    continue
                }
                if progressMs <= syllable.startTimeMs {
                    break
                }

                let duration = max(1, syllable.endTimeMs - syllable.startTimeMs)
                let elapsed = progressMs - syllable.startTimeMs
                highlightedWeight += weight * min(1, max(0, Double(elapsed) / Double(duration)))
                break
            }

            return min(1, max(0, highlightedWeight / totalWeight))
        }

        guard let endTimeMs, endTimeMs > startTimeMs else {
            return progressMs >= startTimeMs ? 1 : 0
        }

        let elapsed = progressMs - startTimeMs
        let duration = endTimeMs - startTimeMs
        return min(1, max(0, Double(elapsed) / Double(duration)))
    }
}
