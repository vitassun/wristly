import AVFoundation
import SwiftUI

struct VoiceView: View {
    let onSend: (String) -> Void
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VoiceModel()

    private var hasTranscript: Bool {
        !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        Image(systemName: voice.recording ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(voice.recording ? Color.red : Color.accentColor)
                        Text(voice.recording ? "正在聆听…" : voice.busy ? "正在识别…" : hasTranscript ? "识别完成" : "豆包语音输入")
                            .font(.headline)
                        if voice.busy && !voice.recording {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    if hasTranscript {
                        Text(voice.transcript)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let error = voice.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if voice.recording {
                        Button {
                            voice.finishRecording()
                        } label: {
                            Label("结束录音", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else if !voice.busy {
                        if hasTranscript {
                            Button {
                                onSend(voice.transcript)
                                dismiss()
                            } label: {
                                Label("发送", systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            HStack(spacing: 8) {
                                TextFieldLink(prompt: Text("编辑识别文字")) {
                                    Text("修改")
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color(white: 0.16), in: Capsule())
                                } onSubmit: { edited in
                                    let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty { voice.transcript = trimmed }
                                }
                                .buttonStyle(.plain)

                                Button("重录") {
                                    voice.start(settings: settings)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Button {
                                voice.start(settings: settings)
                            } label: {
                                Label("开始录音", systemImage: "mic.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Button("取消", role: .cancel) {
                        voice.cancel()
                        dismiss()
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
            .background(Color.black)
            .navigationTitle("语音")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { voice.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voice.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in voice.cancel() }
    }
}
