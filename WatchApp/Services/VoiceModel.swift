import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class VoiceModel: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var recording = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private var capture: AudioCapture?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var task: Task<Void, Never>?
    private var sender: Task<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var generation = UUID()

    func start(settings: SettingsStore) {
        guard !busy else { return }
        busy = true; error = nil; transcript = ""
        let generation = UUID()
        self.generation = generation
        task = Task {
            do {
                let connection = try settings.connection()
                let allowed = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
                }
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                guard allowed else { throw ClientError.message("请在系统设置中允许 Wristly 使用麦克风") }
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 15
                config.timeoutIntervalForResource = 80
                let session = URLSession(configuration: config)
                self.session = session
                let socket = session.webSocketTask(with: connection.request("asr", websocket: true))
                self.socket = socket; socket.resume()
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(75)) } catch { return }
                    self?.fail("识别超时，请重试")
                }
                let first = try await receive(socket)
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                guard first.type == "ready" else { throw ClientError.message(first.message ?? "语音服务尚未就绪") }
                let capture = AudioCapture()
                self.capture = capture
                let stream = try capture.start()
                recording = true
                deadline?.cancel()
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    self?.finishRecording()
                }
                sender = Task {
                    do {
                        for try await data in stream {
                            try Task.checkCancellation()
                            try await socket.send(.data(data))
                        }
                        try Task.checkCancellation()
                        try await socket.send(.string("end"))
                    } catch {
                        if self.generation == generation && !Task.isCancelled { self.error = error.localizedDescription }
                        socket.cancel(with: .goingAway, reason: nil)
                        throw error
                    }
                }
                while true {
                    let result = try await receive(socket)
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    if result.type == "error" { throw ClientError.message(result.message ?? "识别失败") }
                    if result.type == "transcript", let text = result.text { transcript = text }
                    if result.type == "done" { break }
                }
                if transcript.isEmpty { error = "没有识别到文字，请再试一次" }
            } catch {
                guard self.generation == generation else { return }
                if !Task.isCancelled && self.error == nil { self.error = error.localizedDescription }
            }
            guard self.generation == generation else { return }
            cleanup()
        }
    }

    func finishRecording() {
        guard recording else { return }
        recording = false; capture?.stop()
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            self?.fail("等待识别结果超时，请重试")
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        cleanup()
    }
    private func fail(_ message: String) {
        error = message; task?.cancel(); cleanup()
    }
    private func cleanup() {
        capture?.stop(); capture = nil
        sender?.cancel(); sender = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        deadline?.cancel(); deadline = nil
        recording = false; busy = false
    }
    private struct Result: Decodable { var type: String; var text: String?; var message: String? }
    private func receive(_ socket: URLSessionWebSocketTask) async throws -> Result {
        let message = try await socket.receive()
        guard case .string(let text) = message, text.utf8.count < 512_000 else { throw ClientError.message("无效的语音响应") }
        return try JSONDecoder().decode(Result.self, from: Data(text.utf8))
    }
}
