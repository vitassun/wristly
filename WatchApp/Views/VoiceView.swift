import AVFoundation
import SwiftUI

struct VoiceView: View {
    let useText: (String) -> Void
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VoiceModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(voice.recording ? "正在听…" : voice.busy ? "正在识别…" : "豆包语音输入", systemImage: "mic")
                        .font(.headline)
                    if voice.busy { ProgressView().controlSize(.small) }
                    TextField("识别结果，可编辑", text: $voice.transcript).disabled(voice.busy)
                    if let error = voice.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if voice.recording {
                        Button("结束录音", systemImage: "stop.circle") { voice.finishRecording() }
                    } else if !voice.busy {
                        Button(voice.transcript.isEmpty ? "开始录音" : "重新录音", systemImage: "mic.fill") { voice.start(settings: settings) }
                    }
                    Button("使用文字", systemImage: "checkmark") {
                        useText(voice.transcript); dismiss()
                    }.disabled(voice.busy || voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("取消", role: .cancel) { voice.cancel(); dismiss() }
                }
            }.navigationTitle("语音")
        }
        .onDisappear { voice.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voice.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in voice.cancel() }
    }
}
