import Testing
@testable import LyricIslandMac

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
