import Foundation

actor DotnetLyricsServiceClient {
    private let executablePath: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(executablePath: String) {
        self.executablePath = executablePath
    }

    func fetchLyrics(
        for track: TrackInfo,
        sources: [LyricsSource],
        spotifyAccessToken: String?,
        spotifySpDc: String?
    ) async throws -> LyricsPayload {
        let path = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw LyricsServiceError.helperPathMissing
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw LyricsServiceError.helperNotExecutable(path)
        }

        let request = LyricsServiceRequest(
            track: track,
            sources: sources,
            spotifyAccessToken: spotifyAccessToken,
            spotifySpDc: spotifySpDc
        )
        let requestData = try encoder.encode(request)

        let process = Process()
        if path.hasSuffix(".dll") {
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/dotnet")
            process.arguments = [path]
        } else {
            process.executableURL = URL(fileURLWithPath: path)
        }
        process.environment = mergedDotnetEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LyricsServiceError.failedToLaunch(error.localizedDescription)
        }

        if var payload = String(data: requestData, encoding: .utf8) {
            payload.append("\n")
            stdinPipe.fileHandleForWriting.write(Data(payload.utf8))
        } else {
            throw LyricsServiceError.invalidResponse("请求体编码为 UTF-8 失败。")
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw LyricsServiceError.badExit(status: process.terminationStatus, stderr: stderrText)
        }

        guard let response = try? decoder.decode(LyricsServiceResponse.self, from: outData) else {
            let raw = String(data: outData, encoding: .utf8) ?? "<empty>"
            throw LyricsServiceError.invalidResponse(raw)
        }

        if let message = response.error, !message.isEmpty {
            throw LyricsServiceError.remoteError(message)
        }
        guard let payload = response.payload else {
            throw LyricsServiceError.invalidResponse("歌词服务返回中缺少 payload。")
        }
        return payload
    }

    private func mergedDotnetEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["DOTNET_ROOT"] == nil {
            env["DOTNET_ROOT"] = "/opt/homebrew/opt/dotnet/libexec"
        }
        if env["DOTNET_ROOT_ARM64"] == nil {
            env["DOTNET_ROOT_ARM64"] = "/opt/homebrew/opt/dotnet/libexec"
        }
        return env
    }
}
