import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    private static let maxStoredMessages = 30
    private static let persistQueue = DispatchQueue(label: "dev.wristly.persist", qos: .utility)

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var status = ""
    private var task: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pendingDelta = ""
    private var lastDeltaFlush: ContinuousClock.Instant?
    private var generation = UUID()
    private let file: URL

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conversation.json")
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = Array(stored.suffix(Self.maxStoredMessages)).map { message in
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
        pendingDelta = ""; lastDeltaFlush = nil; flushTask?.cancel(); flushTask = nil
        messages.append(ChatMessage(role: .assistant, content: "", state: .streaming))
        persist()
        task = Task {
            do {
                try await ChatAPI().stream(connection: connection, messages: context) { [weak self] name, event in
                    guard let self, self.generation == id, !self.messages.isEmpty else { return }
                    let index = self.messages.count - 1
                    switch name {
                    case "delta":
                        guard let text = event.text, !text.isEmpty else { return }
                        self.enqueueDelta(text, for: id)
                    case "sources":
                        self.flushPendingDelta(for: id)
                        self.messages[index].sources = event.sources ?? []
                    case "status":
                        self.status = event.text ?? ""
                    case "done":
                        self.flushPendingDelta(for: id)
                        self.messages[index].state = .complete
                    default: break
                    }
                }
            } catch {
                guard generation == id else { return }
                flushPendingDelta(for: id)
                messages[messages.count - 1].state = .failed
                self.error = Task.isCancelled ? "回答已停止" : error.localizedDescription
            }
            guard generation == id else { return }
            flushPendingDelta(for: id)
            busy = false; status = ""; persist()
        }
    }

    // Coalesce streaming tokens into ~100ms UI updates while flushing the first token immediately.
    private func enqueueDelta(_ text: String, for id: UUID) {
        pendingDelta += text
        let now = ContinuousClock.now
        let ready = lastDeltaFlush.map { $0.duration(to: now) >= .milliseconds(100) } ?? true
        if ready {
            flushPendingDelta(for: id)
        } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.flushPendingDelta(for: id)
            }
        }
    }

    private func flushPendingDelta(for id: UUID) {
        flushTask?.cancel(); flushTask = nil
        guard generation == id, !pendingDelta.isEmpty, !messages.isEmpty else { return }
        messages[messages.count - 1].content += pendingDelta
        pendingDelta = ""
        lastDeltaFlush = ContinuousClock.now
        if !status.isEmpty { status = "" }
    }

    func stop() { task?.cancel() }
    func newConversation() {
        generation = UUID(); task?.cancel(); task = nil
        flushTask?.cancel(); flushTask = nil; pendingDelta = ""; lastDeltaFlush = nil
        busy = false; messages = []; status = ""; error = nil; persist()
    }
    private func persist() {
        messages = Array(messages.suffix(Self.maxStoredMessages))
        let snapshot = messages
        let destination = file
        Self.persistQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: destination, options: [.atomic, .completeFileProtection])
            } catch {
                let message = "对话暂时无法保存在本机：\(error.localizedDescription)"
                Task { @MainActor [weak self] in self?.error = message }
            }
        }
    }
}
