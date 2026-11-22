import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var diagnostic: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            List {
                Section("后端地址") {
                    TextField("https://…", text: $settings.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("访问令牌（可留空）", text: $settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                if let diagnostic {
                    Section("连接诊断") {
                        Text(diagnostic)
                            .font(.caption2)
                            .foregroundStyle(diagnostic.hasPrefix("连接成功") ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Button {
                        do { try settings.save(); dismiss() } catch { self.error = error.localizedDescription }
                    } label: {
                        Label("保存", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.accentColor)

                    Button {
                        runHealthTest()
                    } label: {
                        Label(testing ? "测试中（≤10秒）…" : "测试连接", systemImage: "network")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(testing)
                }
            }
            .navigationTitle("连接")
            .navigationBarTitleDisplayMode(.inline)
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
