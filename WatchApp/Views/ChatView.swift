import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var chat = ChatStore()
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showVoice = false
    @State private var confirmNew = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chat.messages) { message in
                            MessageView(message: message).equatable()
                        }
                    }

                    if chat.busy {
                        streamingControls
                    }

                    if let error = chat.error {
                        errorCard(error)
                    }

                    if !chat.busy {
                        inputSection
                            .padding(.top, chat.messages.isEmpty ? 4 : 8)
                    }

                    Color.clear.frame(height: 16).id("bottom")
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
            }
            .background(Color.black)
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    reader.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: chat.error) { _, newValue in
                if newValue != nil {
                    withAnimation(.easeOut(duration: 0.2)) {
                        reader.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("Wristly")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { confirmNew = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新对话")
                .disabled(chat.messages.isEmpty && !chat.busy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("连接设置")
            }
        }
        .confirmationDialog("清空当前对话？", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("新建对话", role: .destructive) {
                chat.newConversation()
                draft = ""
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(settings) }
        .sheet(isPresented: $showVoice) {
            VoiceView { text in
                chat.send(text, settings: settings)
            }.environmentObject(settings)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { chat.stop() } }
        .onAppear { if (try? settings.connection()) == nil { showSettings = true } }
    }

    private func sendDraft() {
        guard !chat.busy else { return }
        let originalCount = chat.messages.count
        chat.send(draft, settings: settings)
        if chat.messages.count > originalCount { draft = "" }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("有什么想问的？")
                .font(.headline)
            Text("打字或语音，直接开聊")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var streamingControls: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(chat.status.isEmpty ? "正在回答…" : chat.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                chat.stop()
            } label: {
                Label("停止", systemImage: "stop.fill")
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if chat.messages.last?.state == .failed {
                Button {
                    chat.retry(settings: settings)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                .disabled(chat.busy)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputSection: some View {
        VStack(spacing: 8) {
            TextField("问点什么…", text: $draft)
                .submitLabel(.send)
                .onSubmit(sendDraft)

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: sendDraft) {
                    Label("发送", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                showVoice = true
            } label: {
                Label("豆包语音", systemImage: "mic.fill")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }
}

private struct MessageView: View, Equatable {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 18)
                Text(message.content)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.26), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.content.isEmpty {
                    if message.state != .streaming {
                        Text((try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                             ?? AttributedString(message.content))
                            .font(.body)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(message.content)
                            .font(.body)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.sources) { source in
                            if let url = source.safeURL {
                                Link(destination: url) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "globe")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(source.title)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                if message.state == .failed && !message.content.isEmpty {
                    Text("回答未完成")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}
