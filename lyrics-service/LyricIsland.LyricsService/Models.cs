using System.Text.Json.Serialization;

namespace LyricIsland.LyricsService;

public sealed record TrackInfo(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("artists")] string Artists,
    [property: JsonPropertyName("album")] string Album,
    [property: JsonPropertyName("durationMs")] int DurationMs
);

public sealed record LyricLine(
    [property: JsonPropertyName("text")] string Text,
    [property: JsonPropertyName("subtext")] string? Subtext,
    [property: JsonPropertyName("startTimeMs")] int StartTimeMs,
    [property: JsonPropertyName("endTimeMs")] int? EndTimeMs,
    [property: JsonPropertyName("syllables")] List<LyricSyllable>? Syllables
);

public sealed record LyricSyllable(
    [property: JsonPropertyName("text")] string Text,
    [property: JsonPropertyName("startTimeMs")] int StartTimeMs,
    [property: JsonPropertyName("endTimeMs")] int EndTimeMs
);

public sealed record LyricsPayload(
    [property: JsonPropertyName("source")] string Source,
    [property: JsonPropertyName("track")] TrackInfo Track,
    [property: JsonPropertyName("lines")] List<LyricLine> Lines
);

public sealed record LyricsServiceRequest(
    [property: JsonPropertyName("track")] TrackInfo Track,
    [property: JsonPropertyName("sources")] List<string> Sources,
    [property: JsonPropertyName("spotifyAccessToken")] string? SpotifyAccessToken,
    [property: JsonPropertyName("spotifySpDc")] string? SpotifySpDc
);

public sealed record LyricsServiceResponse(
    [property: JsonPropertyName("payload")] LyricsPayload? Payload,
    [property: JsonPropertyName("error")] string? Error
);
