import SwiftUI

struct InternetView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMode = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if appState.isConnected {
                    modeCard
                    dataCard
                    networkCard
                    trafficCard
                    tipsCard
                } else if appState.isGen2Only {
                    gen2OnlyCard
                } else {
                    EmptyStateView(
                        icon: "network.slash",
                        title: "模块未连接",
                        message: "连接模块后即可切换 USB 上网模式，把 SIM 卡流量变成 Mac 的网络。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
            .padding(18)
        }
        .onAppear {
            if appState.status.usbNetMode >= 0 {
                selectedMode = appState.status.usbNetMode
            }
        }
    }

    private var modeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("上网模式", systemImage: "network")
                    .font(.headline)

                Picker("模式", selection: $selectedMode) {
                    Text("0 · 短信 / 管理").tag(0)
                    Text("1 · USB 上网").tag(1)
                    Text("2 · 实验模式").tag(2)
                    Text("3 · 实验模式").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    StatusBadge(
                        title: "当前：\(appState.status.usbNetModeDescription)",
                        color: appState.status.usbNetMode == 1 ? .green : .secondary
                    )
                    Spacer()
                    Button {
                        Task { await appState.setUSBNetMode(selectedMode) }
                    } label: {
                        Label("应用并重启", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .djGlassProminent()
                    .disabled(selectedMode == appState.status.usbNetMode)

                    Button {
                        Task { await appState.rebootModule() }
                    } label: {
                        Label("仅重启", systemImage: "power")
                    }
                    .djGlass()
                }

                Text("切换模式后模块会重新枚举 USB 接口，连接会短暂中断。上网模式（1）会以 USB 网卡（通常名为 Baiwang）出现在系统网络设置中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 二代模块没有 USB 管理口时的“纯网卡”展示。
    private var gen2OnlyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("二代模块封闭了 USB 管理口，因此无法由本软件切换上网模式；以下只反映 macOS 是否把它识别成网卡。若「系统设置 → 网络」中能看到 Baiwang 并处于已连接，即可把默认出口切到它来上网。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            networkCard
            trafficCard
        }
    }

    private var networkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("网络状态", systemImage: "wifi")
                    .font(.headline)
                MetricRow(title: "系统连接", value: appState.network.pathStatus)
                MetricRow(title: "活跃网卡", value: appState.network.activeInterface.isEmpty ? "无" : appState.network.activeInterface, monospaced: true)
                MetricRow(title: "默认出口", value: appState.network.defaultRouteInterface.isEmpty ? "无" : appState.network.defaultRouteInterface, monospaced: true)
                MetricRow(title: "网关", value: appState.network.defaultGateway.isEmpty ? "无" : appState.network.defaultGateway, monospaced: true)
                HStack {
                    if appState.network.usingModuleAsDefault {
                        StatusBadge(title: "当前正在走 4G 模块", color: .green)
                    } else if appState.network.isAvailable {
                        StatusBadge(title: "模块网卡已就绪，但默认出口不是它", color: .orange)
                    } else {
                        StatusBadge(title: "未发现模块网卡", color: .secondary)
                    }
                    Spacer()
                    if !appState.network.usingModuleAsDefault, appState.network.isAvailable {
                        Button {
                            Task { await appState.makeModuleDefaultRoute() }
                        } label: {
                            Label("设为默认出口", systemImage: "arrow.triangle.branch")
                        }
                        .djGlassProminent()
                        .help("把系统默认出口切换到模块网卡（需要输入 Mac 密码授权）")
                    }
                }
                if let service = appState.moduleService {
                    Text("模块服务：\(service.name)（\(service.device)）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var dataCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("数据连接", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)

                HStack {
                    if appState.pdp.hasDataSession {
                        StatusBadge(title: "数据已附着", color: .green)
                    } else {
                        StatusBadge(title: "数据未附着", color: .orange)
                    }
                    Spacer()
                }

                if appState.pdp.contexts.isEmpty {
                    MetricRow(title: "APN 上下文", value: "未查询到（模块未返回 AT+CGDCONT?）", monospaced: true)
                } else {
                    ForEach(appState.pdp.contexts) { context in
                        HStack(alignment: .top, spacing: 10) {
                            Text("Context \(context.id)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 76, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context.apn.isEmpty ? "APN 未配置" : context.apn)
                                    .font(.callout.weight(.medium))
                                Text("PDN：\(context.pdn.isEmpty ? "—" : context.pdn)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if appState.pdp.activeIDs.contains(context.id) {
                                StatusBadge(title: "已激活", color: .green)
                            } else {
                                StatusBadge(title: "未激活", color: .secondary)
                            }
                        }
                    }
                }

                let address = appState.pdp.addresses.values
                    .first { !$0.isEmpty && $0 != "0.0.0.0" } ?? ""
                MetricRow(
                    title: "模块侧 IP",
                    value: address.isEmpty ? "无（数据未附着）" : address,
                    monospaced: true
                )

                if appState.pdp.contexts.allSatisfy({ $0.apn.isEmpty }) {
                    Text("APN 为空时模块不会建立数据通道。可在 AT 调试页执行：AT+CGDCONT=1,\"IP\",\"你的运营商APN\"，再执行 AT+CGACT=1,1 激活。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var trafficCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("流量统计（本次运行）", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                HStack(spacing: 20) {
                    trafficItem(title: "下载", value: NetworkMonitor.formattedBytes(appState.network.sessionRX), icon: "arrow.down")
                    trafficItem(title: "上传", value: NetworkMonitor.formattedBytes(appState.network.sessionTX), icon: "arrow.up")
                    trafficItem(title: "总计", value: NetworkMonitor.formattedBytes(appState.network.sessionTotal), icon: "sum")
                }
                Divider()
                HStack(spacing: 20) {
                    trafficItem(title: "实时下行", value: NetworkMonitor.formattedSpeed(bytesPerSecond: appState.currentSpeedDown ?? 0), icon: "gauge.with.dots.needle.33percent")
                    trafficItem(title: "实时上行", value: NetworkMonitor.formattedSpeed(bytesPerSecond: appState.currentSpeedUp ?? 0), icon: "gauge.with.dots.needle.67percent")
                }
                Text("流量统计仅供参考，以运营商账单为准。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func trafficItem(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospaced()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tipsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("使用提示", systemImage: "lightbulb")
                    .font(.headline)
                Text("• 确保 SIM 卡套餐有可用流量，注意漫游资费。")
                Text("• 如果切换后代理失效，请检查 Baiwang 网络服务的系统代理设置。")
                Text("• 若默认出口不是模块网卡，可点击上方「设为默认出口」，或到 系统设置 → 网络 → 服务顺序 把它拖到最前。")
                Text("• 模块上网模式下，管理功能（短信 / eSIM）可能不可用，需切回模式 0。")
            }
            .font(.callout)
        }
    }
}

#Preview {
    InternetView()
        .environment(AppState())
}
