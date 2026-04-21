import Foundation

protocol SpotifyPlaybackClient: Sendable {
    func currentPlayback(accessToken: String) async throws -> PlaybackSnapshot
}

actor MockSpotifyPlaybackClient: SpotifyPlaybackClient {
    private let startDate = Date()
    private let demoTrack = TrackInfo(
        id: "spotify:track:demo",
        title: "原型歌曲",
        artists: "歌词岛",
        album: "构建版本 v0",
        durationMs: 214_000,
        artworkURL: nil
    )

    func currentPlayback(accessToken _: String) async throws -> PlaybackSnapshot {
        let elapsedMs = Int(Date().timeIntervalSince(startDate) * 1000)
        let progress = max(0, elapsedMs % demoTrack.durationMs)
        return PlaybackSnapshot(track: demoTrack, progressMs: progress, isPlaying: true)
    }
}

enum SpotifyPlaybackError: LocalizedError {
    case missingAccessToken
    case noActiveDevice
    case failedStatus(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "未配置 Spotify Access Token。"
        case .noActiveDevice:
            return "当前没有可用的 Spotify 播放会话（HTTP 204）。"
        case let .failedStatus(code):
            return "Spotify 播放请求失败，状态码 \(code)。"
        case .malformedResponse:
            return "Spotify 播放响应格式异常。"
        }
    }
}

actor SpotifyWebPlaybackClient: SpotifyPlaybackClient {
    func currentPlayback(accessToken: String) async throws -> PlaybackSnapshot {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw SpotifyPlaybackError.missingAccessToken
        }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.malformedResponse
        }

        if http.statusCode == 204 {
            throw SpotifyPlaybackError.noActiveDevice
        }
        guard http.statusCode == 200 else {
            throw SpotifyPlaybackError.failedStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(SpotifyCurrentlyPlayingResponse.self, from: data)
        guard let item = payload.item else {
            throw SpotifyPlaybackError.malformedResponse
        }

        return PlaybackSnapshot(
            track: TrackInfo(
                id: item.id ?? "spotify:track:unknown",
                title: item.name,
                artists: item.artists.map(\.name).joined(separator: ", "),
                album: item.album.name,
                durationMs: item.durationMs,
                artistArtworkURL: try await fetchPrimaryArtistArtworkURL(
                    accessToken: token,
                    artistID: item.artists.first?.id
                ),
                artworkURL: item.album.preferredArtworkURL
            ),
            progressMs: payload.progressMs ?? 0,
            isPlaying: payload.isPlaying
        )
    }

    private func fetchPrimaryArtistArtworkURL(accessToken: String, artistID: String?) async throws -> String? {
        guard let artistID, !artistID.isEmpty else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/artists/\(artistID)")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.malformedResponse
        }
        guard http.statusCode == 200 else {
            throw SpotifyPlaybackError.failedStatus(http.statusCode)
        }

        let artist = try JSONDecoder().decode(SpotifyArtistDetail.self, from: data)
        return artist.preferredArtworkURL
    }
}

private struct SpotifyCurrentlyPlayingResponse: Decodable {
    let isPlaying: Bool
    let progressMs: Int?
    let item: SpotifyTrack?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case item
    }
}

private struct SpotifyTrack: Decodable {
    let id: String?
    let name: String
    let durationMs: Int
    let album: SpotifyAlbum
    let artists: [SpotifyArtist]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMs = "duration_ms"
        case album
        case artists
    }
}

private struct SpotifyAlbum: Decodable {
    let name: String
    let images: [SpotifyImage]?

    var preferredArtworkURL: String? {
        let list = images ?? []
        if list.isEmpty {
            return nil
        }
        let sorted = list.sorted { lhs, rhs in
            let ldelta = abs((lhs.width ?? 96) - 96)
            let rdelta = abs((rhs.width ?? 96) - 96)
            return ldelta < rdelta
        }
        return sorted.first?.url
    }
}

private struct SpotifyArtist: Decodable {
    let id: String?
    let name: String
}

private struct SpotifyImage: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

private struct SpotifyArtistDetail: Decodable {
    let images: [SpotifyImage]?

    var preferredArtworkURL: String? {
        let list = images ?? []
        if list.isEmpty {
            return nil
        }
        let sorted = list.sorted { lhs, rhs in
            let ldelta = abs((lhs.width ?? 96) - 96)
            let rdelta = abs((rhs.width ?? 96) - 96)
            return ldelta < rdelta
        }
        return sorted.first?.url
    }
}
