import Foundation

struct ChatEvent: Decodable {
    var text: String?
    var message: String?
    var sources: [SourceLink]?
}

struct ChatAPI {
    // Default configuration with caches/cookies disabled and fast failure (waitsForConnectivity = false)
    // so watchOS never silently hangs for 100s when a route is stalled.
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 75
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }()

    // Dedicated short-timeout session for 1-tap diagnostics (hard 10s cap).
    private static let diagnosticSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }()

    static func describe(_ error: Error, url: URL) -> String {
        if let client = error as? ClientError { return client.localizedDescription }
        let ns = error as NSError
        var parts = ["code=\(ns.code)"]
        if let cf = ns.userInfo["_kCFStreamErrorCodeKey"] as? Int { parts.append("cf=\(cf)") }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("u=\(underlying.code)")
            if let ucf = underlying.userInfo["_kCFStreamErrorCodeKey"] as? Int { parts.append("ucf=\(ucf)") }
        }
        if let host = url.host { parts.append(host) }
        return "\(ns.localizedDescription) [\(parts.joined(separator: " "))]"
    }

    func checkHealth(connection: Connection) async -> String {
        var request = connection.request("health")
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        let url = request.url ?? connection.baseURL
        let started = ContinuousClock.now
        do {
            let (data, response) = try await Self.diagnosticSession.data(for: request)
            let ms = Int(started.duration(to: .now).components.seconds * 1000)
                + Int(started.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
            guard let http = response as? HTTPURLResponse else { return "无效响应" }
            let body = String(data: data.prefix(60), encoding: .utf8) ?? ""
            return http.statusCode == 200 ? "连接成功 \(ms)ms \(body)" : "HTTP \(http.statusCode) \(body)"
        } catch {
            let primary = Self.describe(error, url: url)
            let probe = await probeApple()
            return "\(primary)\n\(probe)"
        }
    }

    private func probeApple() async -> String {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return "" }
        var req = URLRequest(url: url)
        req.assumesHTTP3Capable = false
        do {
            let (_, resp) = try await Self.diagnosticSession.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return "Apple HTTPS 正常 (\(code))"
        } catch {
            return "Apple HTTPS 也失败: \(Self.describe(error, url: url))"
        }
    }

    func stream(connection: Connection, messages: [WireMessage],
                onEvent: @MainActor (String, ChatEvent) -> Void) async throws {
        var request = connection.request("chat")
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["messages": messages])
        let url = request.url ?? connection.baseURL
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await Self.sharedSession.bytes(for: request)
        } catch {
            if Task.isCancelled { throw error }
            throw ClientError.message(Self.describe(error, url: url))
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.message("无效的服务器响应") }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401: throw ClientError.message("访问令牌无效，请在设置中检查")
            case 429: throw ClientError.message("请求过于频繁或今日额度已用完，请稍后重试")
            default: throw ClientError.message("后端请求失败（\(http.statusCode)），请检查服务配置")
            }
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else {
            throw ClientError.message("后端没有返回流式响应")
        }
        var parser = SSEDecoder()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let frame = try parser.line(line) else { continue }
            let event = try JSONDecoder().decode(ChatEvent.self, from: Data(frame.data.utf8))
            if frame.event == "error" { throw ClientError.message(event.message ?? "回答中断") }
            await onEvent(frame.event, event)
            if frame.event == "done" { return }
        }
        throw ClientError.message("回答传输中断，请重试")
    }
}
