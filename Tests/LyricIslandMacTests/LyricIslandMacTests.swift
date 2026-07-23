import Foundation
import Testing
@testable import LyricIslandMac

@Test @MainActor
func spotifyLyricsDoNotUseChineseOffset() {
    let model = AppModel(spotifyClient: MockSpotifyPlaybackClient())
    model.lyricsPayload = LyricsPayload(
        source: .spotify,
        track: PlaybackSnapshot.demo.track,
        lines: []
    )

    #expect(model.currentLyricsOffsetSource == .spotify)
    #expect(model.currentLyricsOffsetMs == 0)
}

// MARK: - Line pairing

@Test func linePairFindsCurrentAndNextLineInSortedLyrics() {
    let lines = [
        LyricLine(text: "first", startTimeMs: 1_000, endTimeMs: 2_000),
        LyricLine(text: "second", startTimeMs: 2_000, endTimeMs: 3_000),
        LyricLine(text: "third", startTimeMs: 3_000, endTimeMs: 4_000),
    ]

    let pair = lines.linePair(at: 2_500)

    #expect(pair.current?.text == "second")
    #expect(pair.next?.text == "third")
}

@Test func linePairSwitchesAtTheNextLineStart() {
    let lines = [
        LyricLine(text: "first", startTimeMs: 1_000, endTimeMs: 2_000),
        LyricLine(text: "second", startTimeMs: 2_000, endTimeMs: 3_000),
    ]

    let pair = lines.linePair(at: 2_000)

    #expect(pair.current?.text == "second")
    #expect(pair.next == nil)
}

@Test func linePairKeepsTheSameCursorDuringAnInterlineGap() {
    let lines = [
        LyricLine(text: "first", startTimeMs: 1_000, endTimeMs: 1_500),
        LyricLine(text: "second", startTimeMs: 2_000, endTimeMs: 3_000),
    ]

    let pair = lines.linePair(at: 1_750)

    #expect(pair.current?.text == "first")
    #expect(pair.next?.text == "second")
}

@Test func linePairStillHandlesUnsortedLyrics() {
    let lines = [
        LyricLine(text: "third", startTimeMs: 3_000, endTimeMs: 4_000),
        LyricLine(text: "first", startTimeMs: 1_000, endTimeMs: 2_000),
        LyricLine(text: "second", startTimeMs: 2_000, endTimeMs: 3_000),
    ]

    let pair = lines.linePair(at: 2_500)

    #expect(pair.current?.text == "second")
    #expect(pair.next?.text == "third")
}

@Test func linePairUsesNextLineStartWhenEndTimeIsMissing() {
    let lines = [
        LyricLine(text: "first", startTimeMs: 1_000, endTimeMs: nil),
        LyricLine(text: "second", startTimeMs: 2_000, endTimeMs: nil),
    ]

    let pair = lines.linePair(at: 2_500)

    #expect(pair.current?.text == "second")
    #expect(pair.next == nil)
}

// MARK: - Karaoke progress

@Test func karaokeProgressUsesLinearLineDurationWhenNoSyllables() {
    let line = LyricLine(text: "hello", startTimeMs: 1_000, endTimeMs: 3_000)

    #expect(line.karaokeProgress(at: 1_000) == 0)
    #expect(abs(line.karaokeProgress(at: 2_000) - 0.5) < 0.0001)
    #expect(line.karaokeProgress(at: 3_000) == 1)
    #expect(line.karaokeProgress(at: 4_000) == 1)
}

@Test func karaokeProgressWeightsSyllablesByCharacterCount() {
    let line = LyricLine(
        text: "ab c",
        startTimeMs: 0,
        endTimeMs: 1_000,
        syllables: [
            LyricSyllable(text: "ab", startTimeMs: 0, endTimeMs: 500),
            LyricSyllable(text: "c", startTimeMs: 500, endTimeMs: 1_000),
        ]
    )

    // Midway through first syllable (weight 2 of total 3).
    let midFirst = line.karaokeProgress(at: 250)
    #expect(abs(midFirst - (1.0 / 3.0)) < 0.0001)

    // Fully past first syllable.
    let afterFirst = line.karaokeProgress(at: 500)
    #expect(abs(afterFirst - (2.0 / 3.0)) < 0.0001)

    #expect(line.karaokeProgress(at: 1_000) == 1)
}

// MARK: - LRU cache

@Test func lruCacheEvictsOldestWhenFull() {
    var cache = LRUCache<String, Int>(maxSize: 2)
    cache.set(1, forKey: "a")
    cache.set(2, forKey: "b")
    cache.set(3, forKey: "c")

    #expect(cache.get("a") == nil)
    #expect(cache.get("b") == 2)
    #expect(cache.get("c") == 3)
}

@Test func lruCacheRefreshOnGetPreventsEviction() {
    var cache = LRUCache<String, Int>(maxSize: 2)
    cache.set(1, forKey: "a")
    cache.set(2, forKey: "b")
    _ = cache.get("a") // touch a → b is now oldest
    cache.set(3, forKey: "c")

    #expect(cache.get("b") == nil)
    #expect(cache.get("a") == 1)
    #expect(cache.get("c") == 3)
}

// MARK: - Helper path / dotnet discovery smoke

@Test func defaultHelperPathDoesNotHardcodeUserHome() {
    // Regression: the resolver should return a helper-shaped path without
    // depending on a particular developer's home directory.
    let path = AppModel.defaultHelperPathForTesting
    #expect(
        path.hasSuffix("LyricIsland.LyricsService")
            || path.hasSuffix("LyricIsland.LyricsService.dll")
    )
}

@Test func resolveDotnetExecutableReturnsExistingBinaryOrNil() {
    if let path = DotnetLyricsServiceClient.resolveDotnetExecutableForTesting {
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }
}
