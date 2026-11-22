import SwiftUI

@main
struct WristlyCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct CompanionView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "applewatch")
                        .font(.title)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wristly")
                            .font(.title2.bold())
                        Text("Apple Watch 独立伴侣壳")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("手表端完全独立运行，平时无需打开此 iPhone 应用。", systemImage: "bolt.batteryblock")
                    Label("未启用后台保活或蓝牙常驻同步，iPhone 与手表零额外耗电。", systemImage: "leaf")
                    Label("在 Apple Watch 上打开 Wristly，进入右上角设置填写你的 Worker HTTPS 地址即可开始聊天。", systemImage: "gearshape")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text("提示：请勿卸载此宿主应用，否则系统会同步移除配对的 Apple Watch 应用。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                Spacer()
            }
            .padding(24)
        }
    }
}
