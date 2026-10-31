import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var status = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let file: URL

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conversation.json")
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = Array(stored.suffix(60)).map { message in
                var message = message
                if message.state == .streaming { message.state = .failed }
                return message
            }
        }
    }

    func send(_ text: String, settings: SettingsStore) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        guard text.utf16.count <= 8_000 else { error = "问题最多 8000 字符"; return }
        do {
            let connection = try settings.connection()
            messages.append(ChatMessage(role: .user, content: text))
            respond(connection)
        } catch { self.error = error.localizedDescription }
    }

    func retry(settings: SettingsStore) {
        guard !busy else { return }
        do {
            let connection = try settings.connection()
            if messages.last?.role == .assistant && messages.last?.state == .failed { messages.removeLast() }
            guard messages.last?.role == .user else { return }
            respond(connection)
        } catch { self.error = error.localizedDescription }
    }

    private func respond(_ connection: Connection) {
        let context = ConversationContext.messages(from: messages)
        let id = UUID()
        generation = id; busy = true; error = nil; status = "思考中…"
        messages.append(ChatMessage(role: .assistant, content: "", state: .streaming))
        persist()
        task = Task {
            do {
                try await ChatAPI().stream(connection: connection, messages: context) { [weak self] name, event in
                    guard let self, self.generation == id, !self.messages.isEmpty else { return }
                    let index = self.messages.count - 1
                    switch name {
                    case "delta":
                        self.messages[index].content += event.text ?? ""
                        self.status = ""
                    case "sources": self.messages[index].sources = event.sources ?? []
                    case "status": self.status = event.text ?? ""
                    case "done": self.messages[index].state = .complete
                    default: break
                    }
                }
            } catch {
                guard generation == id else { return }
                messages[messages.count - 1].state = .failed
                self.error = Task.isCancelled ? "回答已停止" : error.localizedDescription
            }
            guard generation == id else { return }
            busy = false; status = ""; persist()
        }
    }

    func stop() { task?.cancel() }
    func newConversation() {
        generation = UUID(); task?.cancel(); task = nil
        busy = false; messages = []; status = ""; error = nil; persist()
    }
    private func persist() {
        messages = Array(messages.suffix(60))
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(messages).write(to: file, options: [.atomic, .completeFileProtection])
        } catch { self.error = "对话暂时无法保存在本机：\(error.localizedDescription)" }
    }
}
