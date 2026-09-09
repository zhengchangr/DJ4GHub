import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var refreshIntervalSelection = 1

    var body: some View {
        Form {
            Section("运行") {
                Toggle("在 Dock 中显示图标", isOn: Binding(
                    get: { appState.showInDock },
                    set: { appState.showInDock = $0 }
                ))
                .help("关闭后应用只在菜单栏常驻，需要时可随时重新打开。")
                Toggle("自动轮询短信", isOn: Binding(
                    get: { appState.autoPollSMS },
                    set: { appState.autoPollSMS = $0 }
                ))
                Toggle("新短信系统通知", isOn: Binding(
                    get: { appState.notificationsEnabled },
                    set: { appState.notificationsEnabled = $0 }
                ))
                Picker("状态刷新间隔", selection: $refreshIntervalSelection) {
                    Text("3 秒").tag(0)
                    Text("5 秒").tag(1)
                    Text("10 秒").tag(2)
                }
                .onChange(of: refreshIntervalSelection) {
                    appState.refreshInterval = [3, 5, 10][refreshIntervalSelection]
                }
            }

            Section("使用提示") {
                Label("上网模式切换后模块会重新枚举，属正常现象。", systemImage: "lightbulb")
                Label("上网时建议检查 Baiwang 网络服务的代理设置。", systemImage: "network")
                Label("短信与 eSIM 需在管理模式（USB 模式 0）下使用。", systemImage: "simcard")
                Label("二代模块只能被识别为潜在网卡，管理功能不可用。", systemImage: "simcard")
                Label("此模块为数据向设计，不支持通话语音，未包含来电功能。", systemImage: "phone.slash")
                Label("请留意 SIM 套餐、漫游资费与流量上限。", systemImage: "exclamationmark.triangle")
            }

            Section("关于") {
                LabeledContent("版本", value: "0.2.0")
                LabeledContent("目标系统", value: "macOS 15 及以上")
                Label("非官方第三方项目，与 DJI、Quectel 无关。", systemImage: "info.circle")
                Label("内置 libusb 1.0.30（LGPL-2.1-or-later）。", systemImage: "doc.text")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
