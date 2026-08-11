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
    private static let preferredChineseLyricsSourceKey = "settings.preferredChineseLyricsSource"
    private static let legacyLyricsOffsetMsKey = "settings.lyricsOffsetMs"
    private static let neteaseLyricsOffsetMsKey = "settings.lyricsOffsetMs.netease"
    private static let qqMusicLyricsOffsetMsKey = "settings.lyricsOffsetMs.qqMusic"

    @Published var playback: PlaybackSnapshot = .demo
    @Published var lyricsPayload: LyricsPayload?
    @Published var currentLine: LyricLine?
    // Only the current line is consumed by the menu-bar view. Keep the look-ahead
    // line internal so each cursor change does not publish a second UI update.
    private var nextLine: LyricLine?
    @Published var overlayVisible = false
    @Published var statusText = "就绪"
    @Published var isSpotifyAuthorizationInProgress = false
    @Published var helperExecutablePath: String = AppModel.defaultHelperExecutablePath {
        didSet {
            guard helperExecutablePath != oldValue else { return }
            cancelLyricsFetch()
        }
    }
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
    @Published var neteaseLyricsOffsetMs: Double {
        didSet {
            let clamped = Self.normalizedLyricsOffset(neteaseLyricsOffsetMs)
            if clamped != neteaseLyricsOffsetMs {
                neteaseLyricsOffsetMs = clamped
                return
            }
            saveLyricsOffset(neteaseLyricsOffsetMs, for: .netease)
        }
    }
    @Published var qqMusicLyricsOffsetMs: Double {
        didSet {
            let clamped = Self.normalizedLyricsOffset(qqMusicLyricsOffsetMs)
            if clamped != qqMusicLyricsOffsetMs {
                qqMusicLyricsOffsetMs = clamped
                return
            }
            saveLyricsOffset(qqMusicLyricsOffsetMs, for: .qqMusic)
        }
    }
    @Published var preferredChineseLyricsSource: LyricsSource {
        didSet {
            UserDefaults.standard.set(preferredChineseLyricsSource.rawValue, forKey: Self.preferredChineseLyricsSourceKey)
            cancelLyricsFetch()
            lyricsCache.removeAll()
            lyricsPayload = nil
            currentLine = nil
            nextLine = nil
            lastLyricsTrackID = nil
            refreshOverlayIfNeeded()
            fetchLyricsFromHelper(autoTriggered: false)
        }
    }

    var chineseLyricsFallbackChain: [LyricsSource] {
        switch preferredChineseLyricsSource {
        case .netease: return [.netease, .qqMusic]
        case .qqMusic: return [.qqMusic, .netease]
        default: return [.netease, .qqMusic]
        }
    }

    var currentLyricsOffsetSource: LyricsSource {
        switch lyricsPayload?.source {
        case .qqMusic:
            return .qqMusic
        case .netease:
            return .netease
        case .spotify:
            return .spotify
        case nil:
            return preferredChineseLyricsSource == .qqMusic ? .qqMusic : .netease
        }
    }

    var currentLyricsOffsetMs: Double {
        get {
            lyricsOffsetMs(for: currentLyricsOffsetSource)
        }
        set {
            setLyricsOffset(newValue, for: currentLyricsOffsetSource)
        }
    }

    private let overlayController = OverlayPanelController()
    private let spotifyClient: SpotifyPlaybackClient
    private let spotifyOAuthClient = SpotifyOAuthClient()
    private var ticker: Timer?
    private var started = false
    private var ticksSinceNetworkSync = 0
    private var playbackProgressAnchorMs = PlaybackSnapshot.demo.progressMs
    private var playbackProgressAnchorDate = Date()
    private(set) var currentPlaybackProgressMs: Int = PlaybackSnapshot.demo.progressMs
    private var effectiveLyricsOffsetMs: Double {
        lyricsOffsetMs(for: currentLyricsOffsetSource)
    }
    private var lyricsProgressMs: Int {
        max(0, currentPlaybackProgressMs + Int(effectiveLyricsOffsetMs))
    }
    private var lastLyricsTrackID: String?
    private var lyricsFetchTrackIDInFlight: String?
    private var lyricsFetchTask: Task<Void, Never>?
    private var lyricsFetchGeneration: UInt64 = 0
    private var lyricsCache = LRUCache<String, LyricsPayload>(maxSize: 20)
    private var isPlaybackRefreshInFlight = false
    private var accessTokenRefreshTask: Task<String, Error>?
    private var overlayAllowedByUser = true
    private var realtimeDisplayActivity: NSObjectProtocol?
    // The overlay owns the 60 Hz animation. The app-level cursor only needs to
    // select the active line, so 30 Hz avoids needless main-thread wakeups while
    // keeping line changes within roughly 33 ms in normal playback.
    private static let localTickIntervalSeconds: TimeInterval = 1.0 / 30.0
    private static let localTickToleranceSeconds: TimeInterval = 0.004
    /// ~8s while playing. Derive tick counts from the local clock so changing
    /// cursor cadence does not change the network request cadence.
    private static let playbackNetworkSyncIntervalTicks: Int = max(
        1,
        Int((8.0 / localTickIntervalSeconds).rounded())
    )
    /// Keep paused-state recovery responsive when playback starts externally.
    private static let playbackNetworkSyncIntervalTicksWhenPaused: Int = max(
        1,
        Int((8.0 / localTickIntervalSeconds).rounded())
    )

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
        let legacyOffset = UserDefaults.standard.object(forKey: Self.legacyLyricsOffsetMsKey) as? Double
        let savedNeteaseOffset = UserDefaults.standard.object(forKey: Self.neteaseLyricsOffsetMsKey) as? Double
        let savedQQMusicOffset = UserDefaults.standard.object(forKey: Self.qqMusicLyricsOffsetMsKey) as? Double
        self.neteaseLyricsOffsetMs = Self.normalizedLyricsOffset(savedNeteaseOffset ?? legacyOffset ?? 0)
        self.qqMusicLyricsOffsetMs = Self.normalizedLyricsOffset(savedQQMusicOffset ?? legacyOffset ?? 0)
        let savedChineseSource = UserDefaults.standard.string(forKey: Self.preferredChineseLyricsSourceKey)
        self.preferredChineseLyricsSource = LyricsSource(rawValue: savedChineseSource ?? "") ?? .netease
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
            MainActor.assumeIsolated {
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
                    cancelLyricsFetch()
                    if let cached = lyricsCache.get(snapshot.track.id) {
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
            } catch SpotifyPlaybackError.noActiveDevice {
                if playback.isPlaying {
                    var paused = playback
                    paused.isPlaying = false
                    applyPlaybackSnapshot(paused)
                    applyOverlayVisibilityPolicy()
                }
                statusText = "当前没有 Spotify 播放会话"
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
        let track = playback.track
        if autoTriggered, lastLyricsTrackID == track.id, lyricsPayload != nil {
            return
        }
        if autoTriggered, lyricsFetchTrackIDInFlight == track.id {
            return
        }

        // The helper resolves sources in request order; retain a generation so a
        // canceled request cannot publish into a newer track/source selection.
        let sources = chineseLyricsFallbackChain + [.spotify]
        lyricsFetchTask?.cancel()
        lyricsFetchGeneration &+= 1
        let requestGeneration = lyricsFetchGeneration
        lyricsFetchTrackIDInFlight = track.id

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.lyricsFetchGeneration == requestGeneration {
                    self.lyricsFetchTrackIDInFlight = nil
                    self.lyricsFetchTask = nil
                }
            }
            let client = DotnetLyricsServiceClient(executablePath: path)
            let token = try? await self.ensureSpotifyAccessToken(forceRefresh: false)
            guard !Task.isCancelled, self.lyricsFetchGeneration == requestGeneration else { return }

            do {
                let payload = try await client.fetchLyrics(
                    for: track,
                    sources: sources,
                    spotifyAccessToken: token,
                    spotifySpDc: self.spotifySpDc
                )
                // Drop stale results if the user already switched tracks.
                guard !Task.isCancelled,
                      self.lyricsFetchGeneration == requestGeneration,
                      self.playback.track.id == track.id else { return }
                guard !payload.lines.isEmpty else {
                    self.statusText = "未找到可用歌词"
                    return
                }

                self.lyricsPayload = payload
                self.currentLine = nil
                self.nextLine = nil
                self.lastLyricsTrackID = track.id
                self.lyricsCache.set(payload, forKey: track.id)
                self.statusText = "歌词加载成功（来源：\(payload.source.displayName)）"
                self.updateLyricCursor()
                self.refreshOverlayIfNeeded()
            } catch {
                guard !Task.isCancelled,
                      self.lyricsFetchGeneration == requestGeneration,
                      self.playback.track.id == track.id else { return }
                self.statusText = autoTriggered
                    ? "Spotify 播放状态已同步，但歌词加载失败: \(error.localizedDescription)"
                    : "歌词服务失败: \(error.localizedDescription)"
            }
        }
        lyricsFetchTask = task
    }

    private func cancelLyricsFetch() {
        lyricsFetchGeneration &+= 1
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        lyricsFetchTrackIDInFlight = nil
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
        let syncInterval = playback.isPlaying
            ? Self.playbackNetworkSyncIntervalTicks
            : Self.playbackNetworkSyncIntervalTicksWhenPaused
        if ticksSinceNetworkSync >= syncInterval {
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

        let pair = lines.linePair(at: lyricsProgressMs)
        let changed = currentLine != pair.current || nextLine != pair.next
        guard changed else { return false }
        let oldText = currentLine?.text ?? "nil"
        let newText = pair.current?.text ?? "nil"
        let lineStart = pair.current?.startTimeMs ?? -1
        Self.klog("cursorChange: at=\(lyricsProgressMs)ms lineStart=\(lineStart) lateness=\(lyricsProgressMs - lineStart)ms old=\"\(oldText.prefix(20))\" -> new=\"\(newText.prefix(20))\"")
        currentLine = pair.current
        nextLine = pair.next
        return true
    }

    private var isPlaybackStillInsideCurrentLyricCursor: Bool {
        if let currentLine {
            let nextStart = nextLine?.startTimeMs ?? Int.max
            // An explicit end can leave a gap before the next line. linePair()
            // still returns this same current/next pair during that gap, so
            // keep the cursor stable until the next line actually starts.
            return lyricsProgressMs >= currentLine.startTimeMs && lyricsProgressMs < nextStart
        }

        if let nextLine {
            return lyricsProgressMs < nextLine.startTimeMs
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
        let progress = currentLine?.karaokeProgress(at: lyricsProgressMs) ?? 0
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
            playbackProgressAnchorMs: playbackProgressAnchorMs + Int(effectiveLyricsOffsetMs),
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

    func lyricsOffsetMs(for source: LyricsSource) -> Double {
        switch source {
        case .netease:
            return neteaseLyricsOffsetMs
        case .qqMusic:
            return qqMusicLyricsOffsetMs
        case .spotify:
            return 0
        }
    }

    func setLyricsOffset(_ offset: Double, for source: LyricsSource) {
        let normalized = Self.normalizedLyricsOffset(offset)
        switch source {
        case .netease:
            neteaseLyricsOffsetMs = normalized
        case .qqMusic:
            qqMusicLyricsOffsetMs = normalized
        case .spotify:
            return
        }
    }

    func clearCurrentLyricsOffset() {
        let source = currentLyricsOffsetSource
        setLyricsOffset(0, for: source)
        statusText = "已清理\(source.displayName)歌词延迟"
    }

    func lyricsOffsetText(for source: LyricsSource) -> String {
        Self.formattedLyricsOffset(lyricsOffsetMs(for: source))
    }

    var lyricsOffsetText: String {
        lyricsOffsetText(for: currentLyricsOffsetSource)
    }

    private func saveLyricsOffset(_ offset: Double, for source: LyricsSource) {
        switch source {
        case .netease:
            UserDefaults.standard.set(offset, forKey: Self.neteaseLyricsOffsetMsKey)
        case .qqMusic:
            UserDefaults.standard.set(offset, forKey: Self.qqMusicLyricsOffsetMsKey)
        case .spotify:
            return
        }
        if currentLyricsOffsetSource == source {
            _ = updateLyricCursor()
            refreshOverlayIfNeeded()
        }
    }

    private static func normalizedLyricsOffset(_ offset: Double) -> Double {
        min(max(offset, -2000), 2000).rounded()
    }

    private static func formattedLyricsOffset(_ offset: Double) -> String {
        let ms = Int(offset)
        if ms == 0 { return "0ms" }
        return ms > 0 ? "+\(ms)ms" : "\(ms)ms"
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

        if let inFlight = accessTokenRefreshTask {
            return try await inFlight.value
        }

        let task = Task { @MainActor in
            try await self.performAccessTokenRefresh(forceRefresh: forceRefresh)
        }
        accessTokenRefreshTask = task
        defer { accessTokenRefreshTask = nil }
        return try await task.value
    }

    private func performAccessTokenRefresh(forceRefresh: Bool) async throws -> String {
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

    /// Exposed for unit tests without opening the full default helper surface.
    nonisolated static var defaultHelperPathForTesting: String { defaultHelperExecutablePath }

    nonisolated private static var defaultHelperExecutablePath: String {
        let fileManager = FileManager.default
        let relativeCandidates = [
            "lyrics-service/LyricIsland.LyricsService/bin/Debug/net10.0/LyricIsland.LyricsService",
            "lyrics-service/LyricIsland.LyricsService/bin/Debug/net10.0/LyricIsland.LyricsService.dll",
            "lyrics-service/LyricIsland.LyricsService/bin/Release/net10.0/LyricIsland.LyricsService",
            "lyrics-service/LyricIsland.LyricsService/bin/Release/net10.0/LyricIsland.LyricsService.dll",
        ]

        if let resourceURL = Bundle.main.resourceURL {
            let bundledExecutable = resourceURL
                .appendingPathComponent("LyricsService", isDirectory: true)
                .appendingPathComponent("LyricIsland.LyricsService")
                .path
            if fileManager.isExecutableFile(atPath: bundledExecutable) {
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

        var roots: [URL] = []
        roots.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))

        // Sources/LyricIslandMac/App/AppModel.swift → repository root while developing via SwiftPM.
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRootFromSource = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        roots.append(repoRootFromSource)

        if let executableURL = Bundle.main.executableURL {
            roots.append(executableURL.deletingLastPathComponent())
        }

        var seen = Set<String>()
        for root in roots {
            let rootPath = root.standardizedFileURL.path
            guard seen.insert(rootPath).inserted else { continue }
            for relative in relativeCandidates {
                let candidate = root.appendingPathComponent(relative).path
                let available = relative.lowercased().hasSuffix(".dll")
                    ? fileManager.fileExists(atPath: candidate)
                    : fileManager.isExecutableFile(atPath: candidate)
                if available {
                    return candidate
                }
            }
        }

        return repoRootFromSource
            .appendingPathComponent(relativeCandidates[0])
            .path
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
