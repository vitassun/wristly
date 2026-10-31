import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("私人后端") {
                    TextField("https://…workers.dev", text: $settings.endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("访问令牌", text: $settings.token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("令牌保存在本机钥匙串。模型与语音密钥只在后端配置。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                Button("保存") {
                    do { try settings.save(); dismiss() } catch { self.error = error.localizedDescription }
                }
            }.navigationTitle("连接")
        }
    }
}
