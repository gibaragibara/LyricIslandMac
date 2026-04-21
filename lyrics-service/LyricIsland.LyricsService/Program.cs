using System.Text.Json;

namespace LyricIsland.LyricsService;

public static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = null,
        WriteIndented = false
    };

    public static async Task<int> Main()
    {
        try
        {
            var input = await Console.In.ReadToEndAsync();
            if (string.IsNullOrWhiteSpace(input))
            {
                await WriteResponseAsync(new LyricsServiceResponse(null, "请求体为空。"));
                return 2;
            }

            var request = JsonSerializer.Deserialize<LyricsServiceRequest>(input, JsonOptions);
            if (request is null)
            {
                await WriteResponseAsync(new LyricsServiceResponse(null, "请求 JSON 无效。"));
                return 2;
            }

            var payload = await LyricProviderFacade.SearchAndResolveAsync(request);
            await WriteResponseAsync(new LyricsServiceResponse(payload, null));
            return 0;
        }
        catch (Exception ex)
        {
            await WriteResponseAsync(new LyricsServiceResponse(null, ex.Message));
            return 1;
        }
    }

    private static async Task WriteResponseAsync(LyricsServiceResponse response)
    {
        var json = JsonSerializer.Serialize(response, JsonOptions);
        await Console.Out.WriteAsync(json);
    }
}
