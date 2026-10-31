import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct Connection: Sendable {
    var baseURL: URL
    var token: String
    func request(_ path: String, websocket: Bool = false) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if websocket {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.scheme = "wss"
            url = parts.url!
        }
        var request = URLRequest(url: url)
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }
}
