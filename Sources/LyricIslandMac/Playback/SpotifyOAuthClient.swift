import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct SpotifyTokenBundle {
    let accessToken: String
    let expiresAt: Date
    let refreshToken: String?
}

enum SpotifyAuthError: LocalizedError {
    case missingClientID
    case missingRefreshToken
    case authorizationAlreadyInProgress
    case browserLaunchFailed
    case callbackServerStartFailed(String)
    case authorizationDenied(String)
    case invalidCallback
    case invalidState
    case failedStatus(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "缺少 Spotify Client ID。"
        case .missingRefreshToken:
            return "尚未完成 Spotify 登录授权。"
        case .authorizationAlreadyInProgress:
            return "Spotify 登录授权正在进行中。"
        case .browserLaunchFailed:
            return "无法打开浏览器启动 Spotify 登录。"
        case let .callbackServerStartFailed(message):
            return "无法启动本地回调服务：\(message)"
        case let .authorizationDenied(message):
            return message.isEmpty ? "Spotify 登录被取消或拒绝。" : "Spotify 登录失败：\(message)"
        case .invalidCallback:
            return "Spotify 回调内容无效。"
        case .invalidState:
            return "Spotify 回调校验失败，请重新登录。"
        case let .failedStatus(code, message):
            if message.isEmpty {
                return "Spotify 令牌请求失败，状态码 \(code)。"
            }
            return "Spotify 令牌请求失败，状态码 \(code)：\(message)"
        case .malformedResponse:
            return "Spotify 令牌响应格式异常。"
        }
    }
}

actor SpotifyOAuthClient {
    static let redirectURIString = "http://127.0.0.1:766/callback"
    static let requiredScopes = ["user-read-currently-playing"]

    private var authorizationInProgress = false

    func authorizeWithPKCE(clientID: String) async throws -> SpotifyTokenBundle {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw SpotifyAuthError.missingClientID
        }
        guard !authorizationInProgress else {
            throw SpotifyAuthError.authorizationAlreadyInProgress
        }
        authorizationInProgress = true
        defer { authorizationInProgress = false }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(from: verifier)
        let state = Self.makeRandomURLSafeString(byteCount: 24)
        let callbackServer = SpotifyAuthorizationCallbackServer()
        try await callbackServer.start(expectedState: state)

        let authorizationURL = try Self.makeAuthorizationURL(
            clientID: normalizedClientID,
            codeChallenge: challenge,
            state: state
        )

        let opened = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }
        guard opened else {
            callbackServer.stop()
            throw SpotifyAuthError.browserLaunchFailed
        }

        let authorizationCode: String
        do {
            authorizationCode = try await callbackServer.waitForCode()
        } catch {
            callbackServer.stop()
            throw error
        }

        return try await exchangeAuthorizationCode(
            clientID: normalizedClientID,
            code: authorizationCode,
            codeVerifier: verifier
        )
    }

    func refreshAccessToken(
        clientID: String,
        refreshToken: String
    ) async throws -> SpotifyTokenBundle {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRefreshToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw SpotifyAuthError.missingClientID
        }
        guard !normalizedRefreshToken.isEmpty else {
            throw SpotifyAuthError.missingRefreshToken
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLSearchParams([
            "grant_type": "refresh_token",
            "refresh_token": normalizedRefreshToken,
            "client_id": normalizedClientID,
        ]).encodedData

        return try await executeTokenRequest(request)
    }

    private func exchangeAuthorizationCode(
        clientID: String,
        code: String,
        codeVerifier: String
    ) async throws -> SpotifyTokenBundle {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLSearchParams([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURIString,
            "code_verifier": codeVerifier,
        ]).encodedData

        return try await executeTokenRequest(request)
    }

    private func executeTokenRequest(_ request: URLRequest) async throws -> SpotifyTokenBundle {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAuthError.malformedResponse
        }

        guard http.statusCode == 200 else {
            let errorPayload = try? JSONDecoder().decode(SpotifyTokenErrorResponse.self, from: data)
            let message = errorPayload?.errorDescription ?? errorPayload?.error ?? ""
            throw SpotifyAuthError.failedStatus(http.statusCode, message)
        }

        guard let payload = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data) else {
            throw SpotifyAuthError.malformedResponse
        }

        return SpotifyTokenBundle(
            accessToken: payload.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            refreshToken: payload.refreshToken
        )
    }

    private static func makeAuthorizationURL(
        clientID: String,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURIString),
            URLQueryItem(name: "scope", value: requiredScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components?.url else {
            throw SpotifyAuthError.invalidCallback
        }
        return url
    }

    private static func makeCodeVerifier() -> String {
        makeRandomURLSafeString(byteCount: 64)
    }

    private static func makeCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func makeRandomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64URLEncodedString()
        }

        let fallback = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return Data(fallback).base64URLEncodedString()
    }
}

private final class SpotifyAuthorizationCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LyricIslandMac.SpotifyAuthCallback")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<String, Error>?
    private var pendingCode: String?
    private var pendingError: Error?
    private var expectedState: String = ""

    func start(expectedState: String) async throws {
        self.expectedState = expectedState
        let port = NWEndpoint.Port(rawValue: 766)!

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            do {
                let listener = try NWListener(using: .tcp, on: port)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection: connection)
                }
                listener.start(queue: queue)
            } catch {
                startContinuation = nil
                continuation.resume(
                    throwing: SpotifyAuthError.callbackServerStartFailed(error.localizedDescription)
                )
            }
        }
    }

    func waitForCode() async throws -> String {
        if let pendingCode {
            self.pendingCode = nil
            stop()
            return pendingCode
        }
        if let pendingError {
            self.pendingError = nil
            stop()
            throw pendingError
        }

        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(throwing: SpotifyAuthError.authorizationDenied("登录流程已取消。"))
        }
        pendingCode = nil
        pendingError = nil
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            startContinuation?.resume()
            startContinuation = nil
        case let .failed(error):
            let wrapped = SpotifyAuthError.callbackServerStartFailed(error.localizedDescription)
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: wrapped)
            } else {
                finish(with: .failure(wrapped))
            }
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                self.sendResponse(
                    status: "500 Internal Server Error",
                    body: Self.errorHTML(message: error.localizedDescription),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.invalidCallback))
                return
            }

            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let requestLine = request.components(separatedBy: "\r\n").first
            else {
                self.sendResponse(
                    status: "400 Bad Request",
                    body: Self.errorHTML(message: "回调请求无效"),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.invalidCallback))
                return
            }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.sendResponse(
                    status: "400 Bad Request",
                    body: Self.errorHTML(message: "回调请求无效"),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.invalidCallback))
                return
            }

            let target = String(parts[1])
            guard let components = URLComponents(string: "http://127.0.0.1\(target)") else {
                self.sendResponse(
                    status: "400 Bad Request",
                    body: Self.errorHTML(message: "回调地址无效"),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.invalidCallback))
                return
            }

            if let errorMessage = components.queryItems?.first(where: { $0.name == "error" })?.value {
                self.sendResponse(
                    status: "200 OK",
                    body: Self.errorHTML(message: errorMessage),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.authorizationDenied(errorMessage)))
                return
            }

            let state = components.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
            guard state == expectedState else {
                self.sendResponse(
                    status: "400 Bad Request",
                    body: Self.errorHTML(message: "状态校验失败，请返回应用重试"),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.invalidState))
                return
            }

            guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                self.sendResponse(
                    status: "400 Bad Request",
                    body: Self.errorHTML(message: "回调中缺少授权码"),
                    on: connection
                )
                self.finish(with: .failure(SpotifyAuthError.invalidCallback))
                return
            }

            self.sendResponse(status: "200 OK", body: Self.successHTML, on: connection)
            self.finish(with: .success(code))
        }
    }

    private func finish(with result: Result<String, Error>) {
        listener?.cancel()
        listener = nil

        if let callbackContinuation {
            self.callbackContinuation = nil
            switch result {
            case let .success(code):
                callbackContinuation.resume(returning: code)
            case let .failure(error):
                callbackContinuation.resume(throwing: error)
            }
        } else {
            switch result {
            case let .success(code):
                pendingCode = code
            case let .failure(error):
                pendingError = error
            }
        }
    }

    private func sendResponse(status: String, body: String, on connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let successHTML = """
    <!doctype html>
    <html lang="zh-CN">
    <head><meta charset="utf-8"><title>Spotify 登录成功</title></head>
    <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;">
    <h2>Spotify 登录成功</h2>
    <p>可以关闭这个页面，返回 LyricIslandMac。</p>
    </body>
    </html>
    """

    private static func errorHTML(message: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head><meta charset="utf-8"><title>Spotify 登录失败</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;">
        <h2>Spotify 登录失败</h2>
        <p>\(message)</p>
        <p>可以关闭这个页面并返回应用重试。</p>
        </body>
        </html>
        """
    }
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct SpotifyTokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct URLSearchParams {
    let values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    var encodedData: Data? {
        let components = values.map { key, value in
            "\(Self.escape(key))=\(Self.escape(value))"
        }.joined(separator: "&")
        return Data(components.utf8)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
