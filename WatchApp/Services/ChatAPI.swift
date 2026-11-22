import Foundation

struct ChatEvent: Decodable {
    var text: String?
    var message: String?
    var sources: [SourceLink]?
}

struct ChatAPI {
    // Reuse a single ephemeral URLSession to preserve TLS/HTTP2 connections across turns
    // and avoid repeated radio handshakes without writing caches or cookies to disk.
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 100
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    func stream(connection: Connection, messages: [WireMessage],
                onEvent: @MainActor (String, ChatEvent) -> Void) async throws {
        var request = connection.request("chat")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["messages": messages])
        let (bytes, response) = try await Self.sharedSession.bytes(for: request)
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
