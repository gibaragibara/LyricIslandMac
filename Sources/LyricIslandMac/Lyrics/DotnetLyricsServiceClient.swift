import Foundation

actor DotnetLyricsServiceClient {
    private static let helperTimeoutSeconds: TimeInterval = 25

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
            guard let dotnet = Self.resolveDotnetExecutable() else {
                throw LyricsServiceError.failedToLaunch("未找到 dotnet 可执行文件，请安装 .NET SDK 或改用已发布的 helper 可执行文件。")
            }
            process.executableURL = URL(fileURLWithPath: dotnet)
            process.arguments = [path]
        } else {
            process.executableURL = URL(fileURLWithPath: path)
        }
        process.environment = Self.mergedDotnetEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = ProcessOutputBuffer()
        let stderrBuffer = ProcessOutputBuffer()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stdoutBuffer.append(chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stderrBuffer.append(chunk)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw LyricsServiceError.failedToLaunch(error.localizedDescription)
        }

        if var payload = String(data: requestData, encoding: .utf8) {
            payload.append("\n")
            stdinPipe.fileHandleForWriting.write(Data(payload.utf8))
        } else {
            throw LyricsServiceError.invalidResponse("请求体编码为 UTF-8 失败。")
        }
        stdinPipe.fileHandleForWriting.closeFile()

        do {
            try await waitForExit(process, timeout: Self.helperTimeoutSeconds)
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        let outData = stdoutBuffer.snapshot()
        let errData = stderrBuffer.snapshot()
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

    nonisolated static var resolveDotnetExecutableForTesting: String? { resolveDotnetExecutable() }

    nonisolated static func resolveDotnetExecutable() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let root = ProcessInfo.processInfo.environment["DOTNET_ROOT"], !root.isEmpty {
            candidates.append((root as NSString).appendingPathComponent("dotnet"))
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathEnv.split(separator: ":") {
                candidates.append("\(directory)/dotnet")
            }
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/dotnet",
            "/usr/local/bin/dotnet",
            "/usr/local/share/dotnet/dotnet",
            "/opt/homebrew/opt/dotnet/libexec/dotnet",
        ])

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    nonisolated static func mergedDotnetEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["DOTNET_ROOT"] == nil {
            let roots = [
                "/opt/homebrew/opt/dotnet/libexec",
                "/usr/local/share/dotnet",
                "/opt/homebrew/Cellar/dotnet",
            ]
            if let root = roots.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                env["DOTNET_ROOT"] = root
            }
        }
        if env["DOTNET_ROOT_ARM64"] == nil, let root = env["DOTNET_ROOT"] {
            env["DOTNET_ROOT_ARM64"] = root
        }
        return env
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { _ in
                        continuation.resume()
                    }
                }
            }

            group.addTask {
                let duration = UInt64(max(timeout, 1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: duration)
                if process.isRunning {
                    process.terminate()
                }
                throw LyricsServiceError.timedOut(timeout)
            }

            defer {
                group.cancelAll()
                process.terminationHandler = nil
            }

            guard let result = await group.nextResult() else { return }
            switch result {
            case .success:
                return
            case let .failure(error):
                throw error
            }
        }
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
