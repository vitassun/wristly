import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var diagnostic: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("后端连接") {
                    TextField("https://…workers.dev", text: $settings.endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("访问令牌（可选）", text: $settings.token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("默认只需填写后端地址。启用私人令牌时再填写，令牌保存在本机钥匙串。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                if let diagnostic {
                    Text(diagnostic)
                        .font(.caption2)
                        .foregroundStyle(diagnostic.hasPrefix("连接成功") ? .green : .orange)
                }
                Button("保存") {
                    do { try settings.save(); dismiss() } catch { self.error = error.localizedDescription }
                }
                Button(testing ? "正在测试…" : "测试连接") {
                    runHealthTest()
                }.disabled(testing)
            }.navigationTitle("连接")
        }
    }

    private func runHealthTest() {
        error = nil
        do {
            let conn = try settings.connection()
            testing = true
            diagnostic = "正在连接 \(conn.baseURL.host ?? "")…"
            Task {
                let result = await ChatAPI().checkHealth(connection: conn)
                diagnostic = result
                testing = false
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
