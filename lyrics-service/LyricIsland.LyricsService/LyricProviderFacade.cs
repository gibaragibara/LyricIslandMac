using Lyricify.Lyrics.Helpers;
using Lyricify.Lyrics.Models;
using Lyricify.Lyrics.Searchers;
using Lyricify.Lyrics.Searchers.Helpers;

namespace LyricIsland.LyricsService;

public static class LyricProviderFacade
{
    private sealed record SourceCandidate(string Source, ISearchResult SearchResult, CompareHelper.MatchType MatchType);
    private sealed record ParsedLyricsResult(LyricsData Main, LyricsData? Translation);
    private sealed record LyricsSelection(LyricsPayload Payload, LyricsFeatures Features);
    private sealed record ConvertedLyrics(List<LyricLine> Lines, LyricsFeatures Features);
    private readonly record struct LyricsFeatures(bool HasTranslation, bool HasSyllables);

    public static async Task<LyricsPayload> SearchAndResolveAsync(LyricsServiceRequest request)
    {
        ConfigureSpotifyProvider(request);
        var normalizedSources = NormalizeSources(request.Sources);
        LyricsSelection? bestSelection = null;

        if (normalizedSources.Contains("spotify"))
        {
            var spotifyDirect = await TryFetchSpotifyDirectAsync(request.Track);
            if (spotifyDirect is not null && spotifyDirect.Lines is { Count: > 0 })
            {
                var converted = ConvertLines(spotifyDirect.Lines, null);
                if (converted.Lines.Count > 0)
                {
                    bestSelection = new LyricsSelection(
                        new LyricsPayload("spotify", request.Track, converted.Lines),
                        converted.Features
                    );
                    if (IsIdeal(bestSelection.Features))
                    {
                        return bestSelection.Payload;
                    }
                }
            }
        }

        var track = new TrackMultiArtistMetadata
        {
            Title = request.Track.Title,
            Artists = SplitArtists(request.Track.Artists),
            Album = request.Track.Album,
            DurationMs = request.Track.DurationMs,
        };

        var candidates = new List<SourceCandidate>();
        foreach (var source in normalizedSources)
        {
            var searcher = BuildSearcher(source);
            if (searcher is null)
            {
                continue;
            }

            try
            {
                var result = await searcher.SearchForResult(track, CompareHelper.MatchType.VeryLow);
                if (result is null)
                {
                    continue;
                }

                var match = result.MatchType ?? CompareHelper.CompareTrack(track, result);
                candidates.Add(new SourceCandidate(source, result, match));
            }
            catch
            {
                // Keep fail-open behavior: a single source failure should not kill the pipeline.
            }
        }

        var ordered = candidates
            .OrderByDescending(c => (int)c.MatchType)
            .ThenBy(c => SourcePriority(c.Source))
            .ToList();

        foreach (var candidate in ordered)
        {
            try
            {
                var parsed = await TryFetchAndParseAsync(candidate);
                if (parsed is null || parsed.Main.Lines is not { Count: > 0 })
                {
                    continue;
                }

                var converted = ConvertLines(parsed.Main.Lines, parsed.Translation?.Lines);
                if (converted.Lines.Count == 0)
                {
                    continue;
                }

                var selection = new LyricsSelection(
                    new LyricsPayload(candidate.Source, request.Track, converted.Lines),
                    converted.Features
                );

                if (ShouldReplace(bestSelection, selection.Features))
                {
                    bestSelection = selection;
                }
                if (IsIdeal(selection.Features))
                {
                    return selection.Payload;
                }
            }
            catch
            {
                // Continue with next candidate.
            }
        }

        if (bestSelection is not null)
        {
            return bestSelection.Payload;
        }
        if (candidates.Count == 0)
        {
            throw new InvalidOperationException("在已选歌词源中未找到可用候选。");
        }

        throw new InvalidOperationException("所有候选歌词源都解析失败。");
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

        if (!string.IsNullOrWhiteSpace(response.Yrc?.Lyric))
        {
            var yrcParsed = ParseHelper.ParseLyrics(response.Yrc.Lyric, LyricsRawTypes.Yrc);
            if (yrcParsed?.Lines is { Count: > 0 })
            {
                var translation = TryParseTranslationData(response.Ytlrc?.Lyric)
                    ?? TryParseTranslationData(response.Tlyric?.Lyric);
                return new ParsedLyricsResult(yrcParsed, translation);
            }
        }

        if (!string.IsNullOrWhiteSpace(response.Lrc?.Lyric))
        {
            var lrcParsed = ParseHelper.ParseLyrics(response.Lrc.Lyric, LyricsRawTypes.Lrc);
            if (lrcParsed?.Lines is not { Count: > 0 })
            {
                return null;
            }

            var translation = TryParseTranslationData(response.Tlyric?.Lyric)
                ?? TryParseTranslationData(response.Ytlrc?.Lyric);
            return new ParsedLyricsResult(lrcParsed, translation);
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

    private static ConvertedLyrics ConvertLines(IReadOnlyList<ILineInfo> lines, IReadOnlyList<ILineInfo>? translationLines)
    {
        var ordered = lines
            .Select((line, index) => new { line, index })
            .Where(x => !string.IsNullOrWhiteSpace(x.line.Text))
            .OrderBy(x => x.line.StartTime ?? int.MaxValue)
            .ThenBy(x => x.index)
            .ToList();

        if (ordered.Count == 0)
        {
            return new ConvertedLyrics(new List<LyricLine>(), new LyricsFeatures(false, false));
        }

        var hasTimedLine = ordered.Any(x => x.line.StartTime.HasValue);
        var output = new List<LyricLine>(ordered.Count);
        var translationsByTime = BuildTranslationLookupByTime(translationLines);
        var translationsByIndex = BuildTranslationLookupByIndex(translationLines);
        var hasTranslation = false;
        var hasSyllables = false;

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
            if (!string.IsNullOrWhiteSpace(subtext))
            {
                hasTranslation = true;
            }
            if (syllables is { Count: > 0 })
            {
                hasSyllables = true;
            }

            output.Add(new LyricLine(text, subtext, start, end, syllables));
        }

        return new ConvertedLyrics(output, new LyricsFeatures(hasTranslation, hasSyllables));
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

    private static bool IsIdeal(LyricsFeatures features)
    {
        return features.HasTranslation && features.HasSyllables;
    }

    private static bool ShouldReplace(LyricsSelection? currentBest, LyricsFeatures candidateFeatures)
    {
        if (currentBest is null)
        {
            return true;
        }

        var best = currentBest.Features;
        if (candidateFeatures.HasTranslation != best.HasTranslation)
        {
            return candidateFeatures.HasTranslation;
        }
        if (candidateFeatures.HasSyllables != best.HasSyllables)
        {
            return candidateFeatures.HasSyllables;
        }

        return false;
    }

    private static List<string> NormalizeSources(IEnumerable<string> sources)
    {
        var normalized = new List<string>();
        foreach (var source in sources)
        {
            var value = source?.Trim().ToLowerInvariant();
            if (value is "spotify" or "qq_music" or "netease")
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

    private static int SourcePriority(string source)
    {
        return source switch
        {
            "spotify" => 0,
            "qq_music" => 1,
            "netease" => 2,
            _ => 99
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
