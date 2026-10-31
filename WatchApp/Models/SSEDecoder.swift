import Foundation

struct SSEFrame: Equatable {
    var event: String
    var data: String
}

struct SSEDecoder {
    private var name = "message"
    private var data: [String] = []
    private var size = 0

    mutating func line(_ input: String) throws -> SSEFrame? {
        let line = input.hasSuffix("\r") ? String(input.dropLast()) : input
        if line.isEmpty {
            defer { name = "message"; data = []; size = 0 }
            return data.isEmpty ? nil : SSEFrame(event: name, data: data.joined(separator: "\n"))
        }
        size += line.utf8.count
        guard size < 512_000 else { throw ClientError.message("服务器响应过大") }
        if line.hasPrefix("event:") { name = field(line, prefix: 6) }
        if line.hasPrefix("data:") { data.append(field(line, prefix: 5)) }
        return nil
    }

    private func field(_ line: String, prefix: Int) -> String {
        let value = String(line.dropFirst(prefix))
        return value.hasPrefix(" ") ? String(value.dropFirst()) : value
    }
}

enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
