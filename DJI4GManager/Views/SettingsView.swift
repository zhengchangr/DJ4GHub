import AppKit
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
                LabeledContent("版本", value: AppUpdater.currentVersion)
                LabeledContent("目标系统", value: "macOS 15 及以上")
                Label("非官方第三方项目，与 DJI、Quectel 无关。", systemImage: "info.circle")
                Label("内置 libusb 1.0.30（LGPL-2.1-or-later）。", systemImage: "doc.text")
            }

            Section("软件更新") {
                switch appState.updatePhase {
                case .idle:
                    Button("检查更新") {
                        Task { await appState.checkForUpdates() }
                    }
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在检查更新…")
                            .foregroundStyle(.secondary)
                    }
                case .found(let update):
                    updateCard(update)
                    Button("下载并安装") {
                        Task { await appState.downloadUpdate(update) }
                    }
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在下载 \(AppUpdater.assetName)…")
                            .foregroundStyle(.secondary)
                    }
                case .downloaded(let update, let stagedApp):
                    Label("下载完成：\(update.name)", systemImage: "checkmark.circle")
                    Button("立即安装并重启") {
                        appState.installUpdate(update, stagedApp: stagedApp)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            NSApp.terminate(nil)
                        }
                    }
                case .installing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在安装，应用将自动重启…")
                            .foregroundStyle(.secondary)
                    }
                case .upToDate:
                    Label("已是最新版本（\(AppUpdater.currentVersion)）", systemImage: "checkmark.circle")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("重试") {
                        Task { await appState.checkForUpdates() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
        .task {
            if case .idle = appState.updatePhase {
                await appState.checkForUpdates()
            }
        }
    }

    @ViewBuilder
    private func updateCard(_ update: AppUpdater.UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("发现新版本：\(update.name)", systemImage: "arrow.down.circle")
            if let notes = update.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
