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
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "sparkle").font(.title2).foregroundStyle(.tint)
                            Text("有什么想问的？").font(.headline)
                            Text("打字或说一句，开始聊天。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    ForEach(chat.messages) { message in MessageView(message: message) }
                    if chat.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(chat.status.isEmpty ? "正在回答…" : chat.status).font(.caption2)
                        }.foregroundStyle(.secondary)
                        Button("停止回答", systemImage: "stop.fill") { chat.stop() }.font(.footnote)
                    }
                    if let error = chat.error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                        if chat.messages.last?.state == .failed {
                            Button("重试", systemImage: "arrow.clockwise") { chat.retry(settings: settings) }.disabled(chat.busy)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 2)
            }
            // Follow new turns, allowing the user to scroll freely during a long answer.
            .onChange(of: chat.messages.count) { _, _ in reader.scrollTo("bottom", anchor: .bottom) }
        }
        .navigationTitle("Wristly")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                TextField("问点什么", text: $draft).submitLabel(.send).onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.plain).font(.title3).accessibilityLabel("发送")
                    .disabled(chat.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { showVoice = true } label: { Image(systemName: "mic.fill") }
                    .buttonStyle(.plain).accessibilityLabel("豆包语音输入").disabled(chat.busy)
            }
            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { confirmNew = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("新对话")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("连接设置")
            }
        }
        .confirmationDialog("清空当前对话？", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("新建对话", role: .destructive) { chat.newConversation(); draft = "" }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(settings) }
        .sheet(isPresented: $showVoice) { VoiceView { draft = $0 }.environmentObject(settings) }
        .onChange(of: scenePhase) { _, phase in if phase == .background { chat.stop() } }
        .onAppear { if (try? settings.connection()) == nil { showSettings = true } }
    }
    private func send() {
        guard !chat.busy else { return }
        let originalCount = chat.messages.count
        chat.send(draft, settings: settings)
        if chat.messages.count > originalCount { draft = "" }
    }
}

private struct MessageView: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .user ? "你" : "Wristly")
                .font(.caption2).foregroundStyle(message.role == .user ? Color.accentColor : .secondary)
            if !message.content.isEmpty {
                // Inline Markdown supports emphasis, code and links; preserve paragraph breaks.
                Text((try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                     ?? AttributedString(message.content))
                    .font(.body).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(message.sources) { source in
                if let url = source.safeURL { Link(source.title, destination: url).font(.caption2).lineLimit(2) }
            }
            if message.state == .failed { Text("回答未完成").font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(message.role == .user ? 10 : 0)
        .background(message.role == .user ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
