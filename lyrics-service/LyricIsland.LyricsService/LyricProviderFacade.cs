using Lyricify.Lyrics.Helpers;
using Lyricify.Lyrics.Helpers.Optimization;
using Lyricify.Lyrics.Models;
using Lyricify.Lyrics.Searchers;
using Lyricify.Lyrics.Searchers.Helpers;

namespace LyricIsland.LyricsService;

public static class LyricProviderFacade
{
    private sealed record SourceCandidate(string Source, ISearchResult SearchResult);
    private sealed record ParsedLyricsResult(LyricsData Main, LyricsData? Translation);
    private sealed record ConvertedLyrics(List<LyricLine> Lines);

    public static async Task<LyricsPayload> SearchAndResolveAsync(LyricsServiceRequest request)
    {
        ConfigureSpotifyProvider(request);
        var normalizedSources = NormalizeSources(request.Sources);

        var track = new TrackMultiArtistMetadata
        {
            Title = request.Track.Title,
            Artists = SplitArtists(request.Track.Artists),
            Album = request.Track.Album,
            DurationMs = request.Track.DurationMs,
        };

        foreach (var source in normalizedSources)
        {
            try
            {
                // Request order is the user-visible source policy: only fall
                // back after the earlier source has no usable lyric payload.
                var payload = await TryResolveSourceAsync(source, request, track);
                if (payload is not null)
                {
                    return payload;
                }
            }
            catch
            {
                // Keep fail-open behavior: a single source failure should not kill the pipeline.
            }
        }

        throw new InvalidOperationException("在已选歌词源中未找到可用歌词。");
    }

    private static async Task<LyricsPayload?> TryResolveSourceAsync(
        string source,
        LyricsServiceRequest request,
        TrackMultiArtistMetadata track
    )
    {
        if (source == "spotify")
        {
            var direct = await TryFetchSpotifyDirectAsync(request.Track);
            if (direct?.Lines is { Count: > 0 })
            {
                var converted = ConvertLines(direct.Lines, null, track);
                if (converted.Lines.Count > 0)
                {
                    return new LyricsPayload("spotify", request.Track, converted.Lines);
                }
            }
        }

        var searcher = BuildSearcher(source);
        if (searcher is null)
        {
            return null;
        }

        var result = await searcher.SearchForResult(track, CompareHelper.MatchType.VeryLow);
        if (result is null)
        {
            return null;
        }

        var parsed = await TryFetchAndParseAsync(new SourceCandidate(source, result));
        if (parsed is null || parsed.Main.Lines is not { Count: > 0 })
        {
            return null;
        }

        var convertedResult = ConvertLines(parsed.Main.Lines, parsed.Translation?.Lines, track);
        return convertedResult.Lines.Count > 0
            ? new LyricsPayload(source, request.Track, convertedResult.Lines)
            : null;
    }

    private static async Task<LyricsData?> TryFetchSpotifyDirectAsync(TrackInfo track)
    {
        var spotifyTrackId = ExtractSpotifyTrackId(track.Id);
        if (string.IsNullOrWhiteSpace(spotifyTrackId))
        {
            return null;
        }

        try
        {
            var rawJson = await ProviderHelper.SpotifyApi.GetLyrics(spotifyTrackId);
            if (string.IsNullOrWhiteSpace(rawJson))
            {
                return null;
            }

            return ParseHelper.ParseLyrics(rawJson, LyricsRawTypes.Spotify);
        }
        catch
        {
            return null;
        }
    }

    private static void ConfigureSpotifyProvider(LyricsServiceRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.SpotifyAccessToken))
        {
            ProviderHelper.SpotifyApi.SetAccessToken(request.SpotifyAccessToken);
        }

        if (!string.IsNullOrWhiteSpace(request.SpotifySpDc))
        {
            ProviderHelper.SpotifyApi.SetSpDc(request.SpotifySpDc);
        }
    }

    private static async Task<ParsedLyricsResult?> TryFetchAndParseAsync(SourceCandidate candidate)
    {
        return candidate.Source switch
        {
            "spotify" => await FetchSpotifyAsync(candidate.SearchResult),
            "qq_music" => await FetchQqMusicAsync(candidate.SearchResult),
            "netease" => await FetchNeteaseAsync(candidate.SearchResult),
            _ => null
        };
    }

    private static async Task<ParsedLyricsResult?> FetchSpotifyAsync(ISearchResult result)
    {
        if (result is not SpotifySearchResult spotify)
        {
            return null;
        }

        var rawJson = await ProviderHelper.SpotifyApi.GetLyrics(spotify.Id);
        if (string.IsNullOrWhiteSpace(rawJson))
        {
            return null;
        }

        var parsed = ParseHelper.ParseLyrics(rawJson, LyricsRawTypes.Spotify);
        return parsed is null ? null : new ParsedLyricsResult(parsed, null);
    }

    private static async Task<ParsedLyricsResult?> FetchQqMusicAsync(ISearchResult result)
    {
        if (result is not QQMusicSearchResult qq)
        {
            return null;
        }

        var lyric = await ProviderHelper.QQMusicApi.GetLyric(qq.Mid);
        var raw = lyric?.Lyric;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var main = ParseHelper.ParseLyrics(raw, LyricsRawTypes.Lrc);
        if (main?.Lines is not { Count: > 0 })
        {
            main = ParseHelper.ParseLyrics(raw, LyricsRawTypes.Qrc);
        }
        if (main?.Lines is not { Count: > 0 })
        {
            return null;
        }

        var translation = TryParseTranslationData(lyric?.Trans);
        return new ParsedLyricsResult(main, translation);
    }

    private static async Task<ParsedLyricsResult?> FetchNeteaseAsync(ISearchResult result)
    {
        if (result is not NeteaseSearchResult netease)
        {
            return null;
        }

        var response = await ProviderHelper.NeteaseApi.GetLyricNew(netease.Id)
            ?? await ProviderHelper.NeteaseApi.GetLyric(netease.Id);
        if (response is null)
        {
            return null;
        }

        var yrcParsed = !string.IsNullOrWhiteSpace(response.Yrc?.Lyric)
            ? ParseHelper.ParseLyrics(response.Yrc.Lyric, LyricsRawTypes.Yrc)
            : null;
        var lrcParsed = !string.IsNullOrWhiteSpace(response.Lrc?.Lyric)
            ? ParseHelper.ParseLyrics(response.Lrc.Lyric, LyricsRawTypes.Lrc)
            : null;
        var yrcTranslation = TryParseTranslationData(response.Ytlrc?.Lyric);
        var lrcTranslation = TryParseTranslationData(response.Tlyric?.Lyric);

        // Some catalog copies contain a sparse YRC overlay even though their
        // ordinary LRC is complete. Keep word timing only when its text coverage
        // is comparable to the line-synced fallback.
        if (yrcParsed?.Lines is { Count: > 0 } yrcLines
            && !HasLowTextCoverage(yrcLines, lrcParsed?.Lines))
        {
            var translation = SelectBestTranslation(yrcLines, yrcTranslation, lrcTranslation);
            return new ParsedLyricsResult(yrcParsed, translation);
        }

        if (lrcParsed?.Lines is { Count: > 0 } lrcLines)
        {
            var translation = SelectBestTranslation(lrcLines, lrcTranslation, yrcTranslation);
            return new ParsedLyricsResult(lrcParsed, translation);
        }

        if (yrcParsed?.Lines is { Count: > 0 } remainingYrcLines)
        {
            var translation = SelectBestTranslation(remainingYrcLines, yrcTranslation, lrcTranslation);
            return new ParsedLyricsResult(yrcParsed, translation);
        }

        return null;
    }

    private static LyricsData? TryParseTranslationData(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var lrc = ParseHelper.ParseLyrics(raw, LyricsRawTypes.Lrc);
        if (lrc?.Lines is { Count: > 0 })
        {
            return lrc;
        }

        var qrc = ParseHelper.ParseLyrics(raw, LyricsRawTypes.Qrc);
        if (qrc?.Lines is { Count: > 0 })
        {
            return qrc;
        }

        var yrc = ParseHelper.ParseLyrics(raw, LyricsRawTypes.Yrc);
        if (yrc?.Lines is { Count: > 0 })
        {
            return yrc;
        }

        return null;
    }

    private static LyricsData? SelectBestTranslation(
        IReadOnlyList<ILineInfo> mainLines,
        params LyricsData?[] candidates
    )
    {
        LyricsData? best = null;
        var bestTimedMatches = -1;
        var bestMeaningfulLines = -1;

        foreach (var candidate in candidates)
        {
            if (candidate?.Lines is not { Count: > 0 } translationLines)
            {
                continue;
            }

            var timedMatches = CountTimedTranslationMatches(mainLines, translationLines);
            var meaningfulLines = translationLines.Count(IsContentLine);
            if (timedMatches > bestTimedMatches
                || (timedMatches == bestTimedMatches && meaningfulLines > bestMeaningfulLines))
            {
                best = candidate;
                bestTimedMatches = timedMatches;
                bestMeaningfulLines = meaningfulLines;
            }
        }

        return best;
    }

    private static int CountTimedTranslationMatches(
        IReadOnlyList<ILineInfo> mainLines,
        IReadOnlyList<ILineInfo> translationLines
    )
    {
        var translationsByTime = BuildTranslationLookupByTime(translationLines);
        if (translationsByTime is null)
        {
            return 0;
        }

        var matches = 0;
        foreach (var line in mainLines)
        {
            if (!IsContentLine(line) || !line.StartTime.HasValue)
            {
                continue;
            }
            if (FindTranslationByTime(translationsByTime, line.StartTime.Value) is not null)
            {
                matches++;
            }
        }
        return matches;
    }

    private static bool HasLowTextCoverage(
        IReadOnlyList<ILineInfo> detailedLines,
        IReadOnlyList<ILineInfo>? fallbackLines
    )
    {
        if (fallbackLines is not { Count: > 0 })
        {
            return false;
        }

        const int minimumReferenceCharacters = 40;
        const double minimumCoverageRatio = 0.72;
        var fallbackCharacters = CountContentCharacters(fallbackLines);
        if (fallbackCharacters < minimumReferenceCharacters)
        {
            return false;
        }

        var detailedCharacters = CountContentCharacters(detailedLines);
        return detailedCharacters < fallbackCharacters * minimumCoverageRatio;
    }

    private static int CountContentCharacters(IEnumerable<ILineInfo> lines)
    {
        return lines
            .Where(IsContentLine)
            .Sum(line => line.Text.Count(character =>
                !char.IsWhiteSpace(character)
                && !char.IsPunctuation(character)
                && !char.IsSymbol(character)));
    }

    private static bool IsContentLine(ILineInfo line)
    {
        return !string.IsNullOrWhiteSpace(line.Text)
            && !InfoLines.IsInfoLine(line.Text);
    }

    private static ConvertedLyrics ConvertLines(
        IReadOnlyList<ILineInfo> lines,
        IReadOnlyList<ILineInfo>? translationLines,
        ITrackMetadata? trackMetadata
    )
    {
        var ordered = lines
            .Select((line, index) => new { line, index })
            .Where(x => !string.IsNullOrWhiteSpace(x.line.Text))
            .Where(x => !InfoLines.IsInfoLine(x.line.Text, trackMetadata))
            .OrderBy(x => x.line.StartTime ?? int.MaxValue)
            .ThenBy(x => x.index)
            .ToList();

        if (ordered.Count == 0)
        {
            return new ConvertedLyrics(new List<LyricLine>());
        }

        var hasTimedLine = ordered.Any(x => x.line.StartTime.HasValue);
        var output = new List<LyricLine>(ordered.Count);
        var translationsByTime = BuildTranslationLookupByTime(translationLines);
        // Timed translation sets can use different line splitting. Falling back
        // to their list index attaches unrelated text to otherwise valid lines.
        var translationsByIndex = translationsByTime is { Count: > 0 }
            ? null
            : BuildTranslationLookupByIndex(translationLines);

        for (var i = 0; i < ordered.Count; i++)
        {
            var current = ordered[i].line;
            var text = current.Text.Trim();
            var start = current.StartTime ?? (hasTimedLine ? 0 : i * 4_000);
            var end = current.EndTime;

            if (end is null && i + 1 < ordered.Count)
            {
                var nextStart = ordered[i + 1].line.StartTime;
                if (nextStart.HasValue && nextStart.Value > start)
                {
                    end = nextStart.Value;
                }
            }

            var subtext = ResolveSubtext(current, text, start, i, translationsByTime, translationsByIndex);
            var syllables = ExtractSyllables(current);
            output.Add(new LyricLine(text, subtext, start, end, syllables));
        }

        return new ConvertedLyrics(output);
    }

    private static string? ResolveSubtext(
        ILineInfo line,
        string mainText,
        int startTimeMs,
        int lineIndex,
        Dictionary<int, string>? translationsByTime,
        List<string>? translationsByIndex
    )
    {
        var embeddedTranslation = (line as IFullLineInfo)?.ChineseTranslation;
        var mappedByTime = FindTranslationByTime(translationsByTime, startTimeMs);
        var mappedByIndex = translationsByIndex is { Count: > 0 } && lineIndex < translationsByIndex.Count
            ? translationsByIndex[lineIndex]
            : null;
        var fallbackSubLine = line.SubLine?.Text;

        var candidates = new[] { embeddedTranslation, mappedByTime, mappedByIndex, fallbackSubLine };
        foreach (var candidate in candidates)
        {
            var normalized = NormalizeSubtext(candidate, mainText);
            if (!string.IsNullOrWhiteSpace(normalized))
            {
                return normalized;
            }
        }

        return null;
    }

    private static Dictionary<int, string>? BuildTranslationLookupByTime(IReadOnlyList<ILineInfo>? lines)
    {
        if (lines is not { Count: > 0 })
        {
            return null;
        }

        var map = new Dictionary<int, string>();
        foreach (var line in lines)
        {
            if (!line.StartTime.HasValue)
            {
                continue;
            }

            var text = NormalizeTranslationText(line.Text);
            if (text is null)
            {
                continue;
            }
            if (!map.ContainsKey(line.StartTime.Value))
            {
                map.Add(line.StartTime.Value, text);
            }
        }

        return map.Count > 0 ? map : null;
    }

    private static List<string>? BuildTranslationLookupByIndex(IReadOnlyList<ILineInfo>? lines)
    {
        if (lines is not { Count: > 0 })
        {
            return null;
        }

        var output = new List<string>(lines.Count);
        foreach (var line in lines)
        {
            output.Add(NormalizeTranslationText(line.Text) ?? string.Empty);
        }

        return output.Count > 0 ? output : null;
    }

    private static string? FindTranslationByTime(Dictionary<int, string>? map, int startTimeMs)
    {
        if (map is null || map.Count == 0)
        {
            return null;
        }
        if (map.TryGetValue(startTimeMs, out var exact))
        {
            return exact;
        }

        const int maxDeltaMs = 750;
        var nearestDelta = int.MaxValue;
        string? nearestText = null;
        foreach (var pair in map)
        {
            var delta = Math.Abs(pair.Key - startTimeMs);
            if (delta < nearestDelta)
            {
                nearestDelta = delta;
                nearestText = pair.Value;
            }
        }

        return nearestDelta <= maxDeltaMs ? nearestText : null;
    }

    private static string? NormalizeTranslationText(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var value = text.Trim();
        return value.Length == 0 ? null : value;
    }

    private static string? NormalizeSubtext(string? text, string mainText)
    {
        var value = NormalizeTranslationText(text);
        if (value is null)
        {
            return null;
        }

        value = value.Trim('(', ')', '[', ']', '（', '）', '【', '】').Trim();
        if (value.Length == 0)
        {
            return null;
        }
        if (string.Equals(value, mainText, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return value;
    }

    private static List<LyricSyllable>? ExtractSyllables(ILineInfo line)
    {
        if (line is not SyllableLineInfo syllableLine || syllableLine.Syllables is not { Count: > 0 })
        {
            return null;
        }

        var output = new List<LyricSyllable>(syllableLine.Syllables.Count);
        foreach (var syllable in syllableLine.Syllables)
        {
            if (string.IsNullOrEmpty(syllable.Text))
            {
                continue;
            }
            if (syllable.EndTime <= syllable.StartTime)
            {
                continue;
            }

            output.Add(new LyricSyllable(syllable.Text, syllable.StartTime, syllable.EndTime));
        }

        return output.Count > 0 ? output : null;
    }

    private static List<string> NormalizeSources(IEnumerable<string> sources)
    {
        var normalized = new List<string>();
        foreach (var source in sources)
        {
            var value = source?.Trim().ToLowerInvariant();
            if (value is ("spotify" or "qq_music" or "netease")
                && !normalized.Contains(value, StringComparer.Ordinal))
            {
                normalized.Add(value);
            }
        }

        if (normalized.Count == 0)
        {
            normalized.Add("spotify");
            normalized.Add("qq_music");
            normalized.Add("netease");
        }

        return normalized;
    }

    private static ISearcher? BuildSearcher(string source)
    {
        return source switch
        {
            "spotify" => new SpotifySearcher(),
            "qq_music" => new QQMusicSearcher(),
            "netease" => new NeteaseSearcher(),
            _ => null
        };
    }

    private static List<string> SplitArtists(string artists)
    {
        return artists
            .Split([",", "/", "&", "、"], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static string? ExtractSpotifyTrackId(string trackId)
    {
        if (string.IsNullOrWhiteSpace(trackId))
        {
            return null;
        }

        if (trackId.StartsWith("spotify:track:", StringComparison.OrdinalIgnoreCase))
        {
            return trackId.Substring("spotify:track:".Length);
        }

        return trackId;
    }
}
