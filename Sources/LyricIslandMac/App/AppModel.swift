import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let spotifyClientIDKey = "settings.spotifyClientID"
    private static let spotifyRefreshTokenKey = "settings.spotifyRefreshToken"
    private static let spotifyAccessTokenKey = "settings.spotifyAccessTokenCache"
    private static let spotifyAccessTokenExpiresAtKey = "settings.spotifyAccessTokenExpiresAt"
    private static let spotifySpDcKey = "settings.spotifySpDc"
    private static let overlayOpacityKey = "settings.overlayOpacity"
    private static let overlayScaleKey = "settings.overlayScale"
    private static let overlayDisplayModeKey = "settings.overlayDisplayMode"
    private static let overlayScreenIDKey = "settings.overlayScreenID"

    @Published var playback: PlaybackSnapshot = .demo
    @Published var lyricsPayload: LyricsPayload?
    @Published var currentLine: LyricLine?
    @Published var nextLine: LyricLine?
    @Published var overlayVisible = false
    @Published var statusText = "就绪"
    @Published var isSpotifyAuthorizationInProgress = false
    @Published var helperExecutablePath: String = AppModel.defaultHelperExecutablePath
    @Published var spotifyClientID: String {
        didSet {
            UserDefaults.standard.set(spotifyClientID, forKey: Self.spotifyClientIDKey)
        }
    }
    @Published var spotifyRefreshToken: String {
        didSet {
            UserDefaults.standard.set(spotifyRefreshToken, forKey: Self.spotifyRefreshTokenKey)
        }
    }
    @Published private(set) var spotifyAccessToken: String {
        didSet {
            UserDefaults.standard.set(spotifyAccessToken, forKey: Self.spotifyAccessTokenKey)
        }
    }
    @Published private(set) var spotifyAccessTokenExpiresAt: Date? {
        didSet {
            UserDefaults.standard.set(
                spotifyAccessTokenExpiresAt?.timeIntervalSince1970,
                forKey: Self.spotifyAccessTokenExpiresAtKey
            )
        }
    }
    @Published var spotifySpDc: String {
        didSet {
            UserDefaults.standard.set(spotifySpDc, forKey: Self.spotifySpDcKey)
        }
    }
    @Published var overlayOpacity: Double {
        didSet {
            let clamped = min(max(overlayOpacity, 0.45), 1.0)
            if clamped != overlayOpacity {
                overlayOpacity = clamped
                return
            }
            UserDefaults.standard.set(overlayOpacity, forKey: Self.overlayOpacityKey)
            refreshOverlayIfNeeded()
        }
    }
    @Published var overlayScale: Double {
        didSet {
            let clamped = min(max(overlayScale, 0.8), 1.3)
            if clamped != overlayScale {
                overlayScale = clamped
                return
            }
            UserDefaults.standard.set(overlayScale, forKey: Self.overlayScaleKey)
            refreshOverlayIfNeeded()
        }
    }
    @Published var overlayDisplayMode: OverlayDisplayMode {
        didSet {
            UserDefaults.standard.set(overlayDisplayMode.rawValue, forKey: Self.overlayDisplayModeKey)
            overlayController.setDisplayMode(overlayDisplayMode)
            refreshOverlayIfNeeded()
        }
    }
    @Published var overlayScreenID: String {
        didSet {
            UserDefaults.standard.set(overlayScreenID, forKey: Self.overlayScreenIDKey)
            overlayController.setPreferredScreenID(overlayScreenID)
            refreshOverlayIfNeeded()
        }
    }
    let selectedSources: [LyricsSource] = [.spotify, .qqMusic, .netease]

    private let overlayController = OverlayPanelController()
    private let spotifyClient: SpotifyPlaybackClient
    private let spotifyOAuthClient = SpotifyOAuthClient()
    private var ticker: Timer?
    private var started = false
    private var ticksSinceNetworkSync = 0
    private var playbackProgressAnchorMs = PlaybackSnapshot.demo.progressMs
    private var playbackProgressAnchorDate = Date()
    private var currentPlaybackProgressMs: Int = PlaybackSnapshot.demo.progressMs
    private var lastLyricsTrackID: String?
    private var lyricsFetchTrackIDInFlight: String?
    private var lyricsCache: [String: LyricsPayload] = [:]
    private static let lyricsCacheMaxSize = 20
    private var isPlaybackRefreshInFlight = false
    private var overlayAllowedByUser = true
    private var realtimeDisplayActivity: NSObjectProtocol?
    private static let localTickIntervalSeconds: TimeInterval = 0.1
    private static let localTickToleranceSeconds: TimeInterval = 0.02
    private static let playbackNetworkSyncIntervalTicks: Int = 80

    init(
        spotifyClient: SpotifyPlaybackClient = SpotifyWebPlaybackClient()
    ) {
        self.spotifyClient = spotifyClient
        self.spotifyClientID = UserDefaults.standard.string(forKey: Self.spotifyClientIDKey) ?? ""
        self.spotifyRefreshToken = UserDefaults.standard.string(forKey: Self.spotifyRefreshTokenKey) ?? ""
        self.spotifyAccessToken = UserDefaults.standard.string(forKey: Self.spotifyAccessTokenKey) ?? ""
        if let ts = UserDefaults.standard.object(forKey: Self.spotifyAccessTokenExpiresAtKey) as? TimeInterval {
            self.spotifyAccessTokenExpiresAt = Date(timeIntervalSince1970: ts)
        } else {
            self.spotifyAccessTokenExpiresAt = nil
        }
        self.spotifySpDc = UserDefaults.standard.string(forKey: Self.spotifySpDcKey) ?? ""
        let savedOpacity = UserDefaults.standard.object(forKey: Self.overlayOpacityKey) as? Double
        self.overlayOpacity = min(max(savedOpacity ?? 0.96, 0.45), 1.0)
        let savedScale = UserDefaults.standard.object(forKey: Self.overlayScaleKey) as? Double
        self.overlayScale = min(max(savedScale ?? 1.0, 0.8), 1.3)
        let savedDisplayMode = UserDefaults.standard.string(forKey: Self.overlayDisplayModeKey)
        self.overlayDisplayMode = OverlayDisplayMode(rawValue: savedDisplayMode ?? "") ?? .compact
        self.overlayScreenID = UserDefaults.standard.string(forKey: Self.overlayScreenIDKey) ?? ""
        overlayController.setDisplayMode(overlayDisplayMode)
        overlayController.setPreferredScreenID(overlayScreenID)
    }

    func start() {
        guard !started else { return }
        started = true
        lyricsPayload = nil
        currentLine = nil
        nextLine = nil
        overlayAllowedByUser = true
        applyOverlayVisibilityPolicy()
        Task { @MainActor in
            do {
                _ = try await ensureSpotifyAccessToken(forceRefresh: false)
                refreshPlayback()
            } catch {
                statusText = "请先填写 Spotify Client ID，并完成网页登录授权。"
            }
        }
        let timer = Timer(timeInterval: Self.localTickIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = Self.localTickToleranceSeconds
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func toggleOverlay() {
        overlayAllowedByUser.toggle()
        applyOverlayVisibilityPolicy()
        if overlayAllowedByUser {
            if !playback.isPlaying {
                statusText = "歌词岛已启用，恢复播放后会自动显示。"
            } else {
                statusText = "歌词岛悬浮层已显示。"
            }
        } else {
            statusText = "歌词岛悬浮层已手动关闭。"
        }
    }

    func refreshPlayback() {
        guard !isPlaybackRefreshInFlight else { return }
        isPlaybackRefreshInFlight = true
        ticksSinceNetworkSync = 0
        let client = spotifyClient
        Task { @MainActor in
            defer { isPlaybackRefreshInFlight = false }
            do {
                let token = try await ensureSpotifyAccessToken(forceRefresh: false)
                let requestStartedAt = Date()
                let snapshot = try await client.currentPlayback(accessToken: token)
                let responseReceivedAt = Date()
                let snapshotEvaluatedAt = Date(
                    timeIntervalSince1970: (requestStartedAt.timeIntervalSince1970 + responseReceivedAt.timeIntervalSince1970) / 2
                )
                let trackChanged = playback.track.id != snapshot.track.id
                applyPlaybackSnapshot(snapshot, evaluatedAt: snapshotEvaluatedAt)
                if trackChanged {
                    if let cached = lyricsCache[snapshot.track.id] {
                        lyricsPayload = cached
                        currentLine = nil
                        nextLine = nil
                        lastLyricsTrackID = snapshot.track.id
                        statusText = "歌词已从缓存加载（来源：\(cached.source.displayName)）"
                    } else {
                        lyricsPayload = nil
                        currentLine = nil
                        nextLine = nil
                    }
                }
                updateLyricCursor()
                applyOverlayVisibilityPolicy()
                refreshOverlayIfNeeded()
                if trackChanged || lyricsPayload == nil {
                    if lyricsPayload == nil {
                        statusText = "Spotify 播放状态已同步，正在加载歌词"
                    }
                    fetchLyricsFromHelper(autoTriggered: true)
                } else {
                    statusText = "Spotify 播放状态已同步"
                }
                if trackChanged, let artistID = snapshot.primaryArtistID {
                    fetchArtistArtwork(token: token, artistID: artistID, trackID: snapshot.track.id)
                }
            } catch {
                statusText = "Spotify 同步失败: \(error.localizedDescription)"
            }
        }
    }

    private func fetchArtistArtwork(token: String, artistID: String, trackID: String) {
        let client = spotifyClient
        Task { @MainActor in
            let url = try? await client.fetchArtistArtworkURL(accessToken: token, artistID: artistID)
            guard playback.track.id == trackID else { return }
            playback.track.artistArtworkURL = url
            refreshOverlayIfNeeded()
        }
    }

    func fetchLyricsFromHelper(autoTriggered: Bool = false) {
        let path = helperExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = selectedSources
        let track = playback.track
        if autoTriggered, lastLyricsTrackID == track.id, lyricsPayload != nil {
            return
        }
        if autoTriggered, lyricsFetchTrackIDInFlight == track.id {
            return
        }

        Task { @MainActor in
            lyricsFetchTrackIDInFlight = track.id
            defer {
                if lyricsFetchTrackIDInFlight == track.id {
                    lyricsFetchTrackIDInFlight = nil
                }
            }
            let client = DotnetLyricsServiceClient(executablePath: path)
            do {
                let token = try? await ensureSpotifyAccessToken(forceRefresh: false)
                let payload = try await client.fetchLyrics(
                    for: track,
                    sources: sources,
                    spotifyAccessToken: token,
                    spotifySpDc: spotifySpDc
                )
                lyricsPayload = payload
                currentLine = nil
                nextLine = nil
                lastLyricsTrackID = track.id
                if lyricsCache.count >= Self.lyricsCacheMaxSize {
                    lyricsCache.removeAll()
                }
                lyricsCache[track.id] = payload
                statusText = "歌词加载成功（来源：\(payload.source.displayName)）"
                updateLyricCursor()
                refreshOverlayIfNeeded()
            } catch {
                statusText = autoTriggered
                    ? "Spotify 播放状态已同步，但歌词加载失败: \(error.localizedDescription)"
                    : "歌词服务失败: \(error.localizedDescription)"
            }
        }
    }

    func refreshSpotifyAccessTokenManually() {
        Task { @MainActor in
            do {
                _ = try await ensureSpotifyAccessToken(forceRefresh: true)
                statusText = "Spotify 访问令牌已刷新"
            } catch {
                statusText = "Spotify 令牌刷新失败: \(error.localizedDescription)"
            }
        }
    }

    func authorizeSpotifyViaBrowser() {
        let clientID = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            statusText = "请先填写 Spotify Client ID。"
            return
        }
        guard !isSpotifyAuthorizationInProgress else { return }

        isSpotifyAuthorizationInProgress = true
        statusText = "正在打开 Spotify 登录页…"

        Task { @MainActor in
            defer { isSpotifyAuthorizationInProgress = false }

            do {
                let bundle = try await spotifyOAuthClient.authorizeWithPKCE(clientID: clientID)
                spotifyAccessToken = bundle.accessToken
                spotifyAccessTokenExpiresAt = bundle.expiresAt
                if let refreshToken = bundle.refreshToken, !refreshToken.isEmpty {
                    spotifyRefreshToken = refreshToken
                }
                statusText = "Spotify 登录授权成功"
                refreshPlayback()
            } catch {
                statusText = "Spotify 登录失败: \(error.localizedDescription)"
            }
        }
    }

    func clearSpotifyAuthorization() {
        spotifyRefreshToken = ""
        spotifyAccessToken = ""
        spotifyAccessTokenExpiresAt = nil
        statusText = "已清除 Spotify 授权信息"
    }

    func openSpotifyDeveloperDashboard() {
        guard let url = URL(string: "https://developer.spotify.com/dashboard") else { return }
        NSWorkspace.shared.open(url)
    }

    private func tick() {
        updateLocalPlaybackProgress()
        ticksSinceNetworkSync += 1
        if ticksSinceNetworkSync >= Self.playbackNetworkSyncIntervalTicks {
            ticksSinceNetworkSync = 0
            refreshPlayback()
        }
        if updateLyricCursor() {
            refreshOverlayIfNeeded()
        }
    }

    private func applyPlaybackSnapshot(_ snapshot: PlaybackSnapshot, evaluatedAt: Date = Date()) {
        var updated = snapshot
        if updated.track.id == playback.track.id, updated.track.artistArtworkURL == nil {
            updated.track.artistArtworkURL = playback.track.artistArtworkURL
        }

        let now = Date()
        let trackChanged = playback.track.id != updated.track.id
        let playStateChanged = playback.isPlaying != updated.isPlaying

        let priorProjectedMs: Int
        if !trackChanged, playback.isPlaying {
            let elapsedMs = Int(now.timeIntervalSince(playbackProgressAnchorDate) * 1_000)
            priorProjectedMs = max(0, playbackProgressAnchorMs + elapsedMs)
        } else {
            priorProjectedMs = playback.progressMs
        }

        let snapshotAgeMs = max(0, Int(now.timeIntervalSince(evaluatedAt) * 1_000))
        let reportedNowMs = updated.isPlaying
            ? min(updated.track.durationMs, max(0, updated.progressMs + snapshotAgeMs))
            : updated.progressMs

        let delta = trackChanged ? Int.max : abs(reportedNowMs - priorProjectedMs)
        let shouldResetAnchor = trackChanged || playStateChanged || delta > 500

        Self.klog("applySnapshot: track=\(updated.track.id) playing=\(updated.isPlaying) reported=\(updated.progressMs) snapshotAge=\(snapshotAgeMs)ms priorProjected=\(priorProjectedMs) reportedNow=\(reportedNowMs) delta=\(delta)ms resetAnchor=\(shouldResetAnchor)")

        if shouldResetAnchor {
            playbackProgressAnchorMs = updated.progressMs
            playbackProgressAnchorDate = evaluatedAt
            updated.progressMs = reportedNowMs
        } else {
            updated.progressMs = priorProjectedMs
        }
        currentPlaybackProgressMs = updated.progressMs

        playback = updated
    }

    private func updateLocalPlaybackProgress(now: Date = Date()) {
        guard playback.isPlaying else {
            playbackProgressAnchorMs = playback.progressMs
            playbackProgressAnchorDate = now
            currentPlaybackProgressMs = playback.progressMs
            return
        }

        let elapsedMs = Int(now.timeIntervalSince(playbackProgressAnchorDate) * 1_000)
        let projectedProgress = min(playback.track.durationMs, max(0, playbackProgressAnchorMs + elapsedMs))
        currentPlaybackProgressMs = projectedProgress
        // Throttle the @Published mutation: only update playback.progressMs when the
        // visible second changes, so we don't trigger SwiftUI Observation churn 10x/sec.
        if playback.progressMs / 1000 != projectedProgress / 1000 {
            playback.progressMs = projectedProgress
        }
    }

    private static let karaokeDebugEnabled = ProcessInfo.processInfo.environment["KARAOKE_DEBUG"] == "1"

    fileprivate static func klog(_ message: @autoclosure () -> String) {
        guard karaokeDebugEnabled else { return }
        let t = Date().timeIntervalSinceReferenceDate
        print("[karaoke \(String(format: "%.3f", t))] \(message())")
    }

    @discardableResult
    private func updateLyricCursor() -> Bool {
        guard let lines = lyricsPayload?.lines else {
            let changed = currentLine != nil || nextLine != nil
            currentLine = nil
            nextLine = nil
            return changed
        }

        if isPlaybackStillInsideCurrentLyricCursor {
            return false
        }

        let pair = lines.linePair(at: currentPlaybackProgressMs)
        let changed = currentLine != pair.current || nextLine != pair.next
        guard changed else { return false }
        let oldText = currentLine?.text ?? "nil"
        let newText = pair.current?.text ?? "nil"
        let lineStart = pair.current?.startTimeMs ?? -1
        Self.klog("cursorChange: at=\(currentPlaybackProgressMs)ms lineStart=\(lineStart) lateness=\(currentPlaybackProgressMs - lineStart)ms old=\"\(oldText.prefix(20))\" -> new=\"\(newText.prefix(20))\"")
        currentLine = pair.current
        nextLine = pair.next
        return true
    }

    private var isPlaybackStillInsideCurrentLyricCursor: Bool {
        if let currentLine {
            let explicitEnd = currentLine.endTimeMs ?? Int.max
            let nextStart = nextLine?.startTimeMs ?? Int.max
            let effectiveEnd = min(explicitEnd, nextStart)
            return currentPlaybackProgressMs >= currentLine.startTimeMs && currentPlaybackProgressMs < effectiveEnd
        }

        if let nextLine {
            return currentPlaybackProgressMs < nextLine.startTimeMs
        }

        return false
    }

    private func refreshOverlayIfNeeded() {
        guard overlayVisible else { return }
        overlayController.show(model: makeOverlayModel())
    }

    private func applyOverlayVisibilityPolicy() {
        let shouldShow = overlayAllowedByUser && playback.isPlaying
        guard shouldShow != overlayVisible else {
            if shouldShow {
                overlayController.show(model: makeOverlayModel())
            }
            updateRealtimeDisplayActivity()
            return
        }

        overlayVisible = shouldShow
        if shouldShow {
            overlayController.show(model: makeOverlayModel())
        } else {
            overlayController.hide()
        }
        updateRealtimeDisplayActivity()
    }

    private func updateRealtimeDisplayActivity() {
        let needsRealtimeUpdates = overlayVisible && playback.isPlaying
        if needsRealtimeUpdates {
            guard realtimeDisplayActivity == nil else { return }
            realtimeDisplayActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Keep karaoke lyric progress smooth while playback overlay is visible."
            )
        } else {
            endRealtimeDisplayActivity()
        }
    }

    private func endRealtimeDisplayActivity() {
        guard let realtimeDisplayActivity else { return }
        ProcessInfo.processInfo.endActivity(realtimeDisplayActivity)
        self.realtimeDisplayActivity = nil
    }

    private func makeOverlayModel() -> OverlayViewModel {
        let subline = currentLine?.subtext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let progress = currentLine?.karaokeProgress(at: currentPlaybackProgressMs) ?? 0
        let compactPrimary = currentLine?.text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? playback.track.title
        let compactSecondary = subline?.nonEmpty ?? playback.track.artists
        return OverlayViewModel(
            title: playback.track.displayTitle,
            subtitle: playback.track.album,
            artistArtworkURL: playback.track.artistArtworkURL,
            currentLine: currentLine?.text ?? "当前时间点暂无歌词行",
            currentSubline: subline?.isEmpty == false ? subline : nil,
            compactPrimaryLine: compactPrimary,
            compactSecondaryLine: compactSecondary,
            artworkURL: playback.track.artworkURL,
            currentProgress: progress,
            currentLyricLine: currentLine,
            playbackProgressAnchorMs: playbackProgressAnchorMs,
            playbackProgressAnchorDate: playbackProgressAnchorDate,
            nextLine: nextLine?.text,
            isPlaying: playback.isPlaying,
            overlayOpacity: overlayOpacity,
            overlayScale: overlayScale
        )
    }

    var hasSpotifyToken: Bool {
        !spotifyAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSpotifyRefreshToken: Bool {
        !spotifyRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var spotifyTokenStatusText: String {
        if hasSpotifyToken {
            if let expiresAt = spotifyAccessTokenExpiresAt {
                return "Spotify 访问令牌：已获取（到期 \(Self.tokenTimeFormatter.string(from: expiresAt))）"
            }
            return "Spotify 访问令牌：已获取"
        }
        if hasSpotifyRefreshToken {
            return "Spotify 已授权，可按需刷新访问令牌"
        }
        return "Spotify 访问令牌：未获取"
    }

    var spotifyAuthorizationButtonTitle: String {
        hasSpotifyRefreshToken ? "重新登录 Spotify" : "登录 Spotify"
    }

    var spotifyRedirectURI: String {
        SpotifyOAuthClient.redirectURIString
    }

    var spotifyScopeSummary: String {
        SpotifyOAuthClient.requiredScopes.joined(separator: ", ")
    }

    var overlayOpacityPercentText: String {
        "\(Int((overlayOpacity * 100).rounded()))%"
    }

    var overlayScalePercentText: String {
        "\(Int((overlayScale * 100).rounded()))%"
    }

    var overlayToggleButtonTitle: String {
        if overlayAllowedByUser {
            return playback.isPlaying ? "手动关闭歌词岛悬浮层" : "关闭歌词岛自动显示"
        }
        return playback.isPlaying ? "手动显示歌词岛悬浮层" : "允许播放时自动显示歌词岛"
    }

    var overlayVisibilityStatusText: String {
        if !overlayAllowedByUser {
            return "已手动关闭，恢复播放也不会自动显示。"
        }
        return playback.isPlaying
            ? "播放中：歌词岛会自动显示。"
            : "已暂停：歌词岛会自动隐藏。"
    }

    var overlayScreenOptions: [OverlayScreenOption] {
        let options = OverlayPanelController.availableScreenOptions()
        if overlayScreenID.isEmpty, let first = options.first {
            return [OverlayScreenOption(id: "", title: "主屏幕（当前：\(first.title)）")] + options
        }
        return [OverlayScreenOption(id: "", title: "主屏幕")] + options
    }

    var overlayScreenLabel: String {
        if overlayScreenID.isEmpty {
            return "主屏幕"
        }
        return overlayScreenOptions.first(where: { $0.id == overlayScreenID })?.title ?? "已选屏幕不可用"
    }

    private var hasSpotifyOAuthCredentials: Bool {
        !spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !spotifyRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ensureSpotifyAccessToken(forceRefresh: Bool) async throws -> String {
        let now = Date()
        if !forceRefresh,
           !spotifyAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let expiresAt = spotifyAccessTokenExpiresAt,
           expiresAt.timeIntervalSince(now) > 90 {
            return spotifyAccessToken
        }

        guard hasSpotifyOAuthCredentials else {
            if !spotifyAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return spotifyAccessToken
            }
            throw SpotifyAuthError.missingRefreshToken
        }

        let tokenBundle = try await spotifyOAuthClient.refreshAccessToken(
            clientID: spotifyClientID,
            refreshToken: spotifyRefreshToken
        )
        spotifyAccessToken = tokenBundle.accessToken
        spotifyAccessTokenExpiresAt = tokenBundle.expiresAt
        if let refreshedToken = tokenBundle.refreshToken, !refreshedToken.isEmpty {
            spotifyRefreshToken = refreshedToken
        }
        return spotifyAccessToken
    }

    private static let tokenTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static var defaultHelperExecutablePath: String {
        let fileManager = FileManager.default

        if let resourceURL = Bundle.main.resourceURL {
            let bundledExecutable = resourceURL
                .appendingPathComponent("LyricsService", isDirectory: true)
                .appendingPathComponent("LyricIsland.LyricsService")
                .path
            if fileManager.fileExists(atPath: bundledExecutable) {
                return bundledExecutable
            }

            let bundledDLL = resourceURL
                .appendingPathComponent("LyricsService", isDirectory: true)
                .appendingPathComponent("LyricIsland.LyricsService.dll")
                .path
            if fileManager.fileExists(atPath: bundledDLL) {
                return bundledDLL
            }
        }

        let repoExecutable = "/Users/gibara/LyricIslandMac/lyrics-service/LyricIsland.LyricsService/bin/Debug/net10.0/LyricIsland.LyricsService"
        if fileManager.fileExists(atPath: repoExecutable) {
            return repoExecutable
        }

        return "/Users/gibara/LyricIslandMac/lyrics-service/LyricIsland.LyricsService/bin/Debug/net10.0/LyricIsland.LyricsService.dll"
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
