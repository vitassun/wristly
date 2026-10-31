import Foundation

struct SourceLink: Codable, Identifiable, Equatable {
    var title: String
    var url: String
    var snippet: String
    var id: String { url }
    var safeURL: URL? {
        guard let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? "") else { return nil }
        return value
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }
    enum State: String, Codable { case complete, streaming, failed }
    var id = UUID()
    var role: Role
    var content: String
    var sources: [SourceLink] = []
    var state: State = .complete
}

struct WireMessage: Codable, Equatable {
    var role: String
    var content: String
}

enum ConversationContext {
    static func messages(from messages: [ChatMessage]) -> [WireMessage] {
        var result: [WireMessage] = []
        var length = 0
        for message in messages.suffix(24).reversed() where message.state == .complete && !message.content.isEmpty {
            let text = String(decoding: message.content.utf16.prefix(8_000), as: UTF16.self)
            let units = text.utf16.count
            if length + units > 24_000 { break }
            result.insert(WireMessage(role: message.role.rawValue, content: text), at: 0)
            length += units
        }
        while result.first?.role == "assistant" { result.removeFirst() }
        return result
    }
}
