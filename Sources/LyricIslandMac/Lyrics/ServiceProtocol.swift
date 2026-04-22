import Foundation

struct LyricsServiceRequest: Codable {
    var track: TrackInfo
    var sources: [LyricsSource]
    var spotifyAccessToken: String?
    var spotifySpDc: String?
}

struct LyricsServiceResponse: Codable {
    var payload: LyricsPayload?
    var error: String?
}

enum LyricsServiceError: LocalizedError {
    case helperPathMissing
    case helperNotExecutable(String)
    case failedToLaunch(String)
    case timedOut(TimeInterval)
    case badExit(status: Int32, stderr: String)
    case invalidResponse(String)
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case .helperPathMissing:
            return "歌词服务可执行路径为空。"
        case let .helperNotExecutable(path):
            return "歌词服务路径不存在或不可执行: \(path)"
        case let .failedToLaunch(reason):
            return "启动歌词服务失败: \(reason)"
        case let .timedOut(timeout):
            return "歌词服务超时（\(Int(timeout.rounded())) 秒）。"
        case let .badExit(status, stderr):
            return "歌词服务异常退出（状态码 \(status)）。\(stderr)"
        case let .invalidResponse(raw):
            return "歌词服务返回格式无效: \(raw)"
        case let .remoteError(message):
            return "歌词服务错误: \(message)"
        }
    }
}
