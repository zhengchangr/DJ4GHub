import SwiftUI

struct ESIMView: View {
    @Environment(AppState.self) private var appState
    @State private var profileToDelete: ESIMProfile?
    @State private var profileToRename: ESIMProfile?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if appState.isConnected {
                    infoCard
                    experimentalCard
                    profilesCard
                } else {
                    EmptyStateView(
                        icon: "simcard.slash",
                        title: "模块未连接",
                        message: "eSIM 功能需要模块处于管理模式（USB 模式 0）且插入兼容的 eUICC 卡片。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
            .padding(18)
        }
        .toolbar {
            ToolbarItem {
                if appState.esimBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await appState.refreshESIM() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("读取 eUICC 信息")
                }
            }
        }
        .alert("删除 Profile", isPresented: .init(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let profile = profileToDelete {
                    Task { await appState.deleteProfile(iccid: profile.iccid) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从 eUICC 卡片删除此 Profile，此操作通常不可恢复。")
        }
        .alert("修改 Profile 名称", isPresented: .init(get: { profileToRename != nil }, set: { if !$0 { profileToRename = nil } })) {
            TextField("名称", text: $renameText)
            Button("保存") {
                if let profile = profileToRename {
                    Task { await appState.renameProfile(iccid: profile.iccid, nickname: renameText) }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var infoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("eUICC 卡片", systemImage: "simcard")
                    .font(.headline)
                MetricRow(title: "EID", value: appState.esim.eid.isEmpty ? "未读取" : appState.esim.eid, monospaced: true)
                MetricRow(title: "检测到的应用", value: appState.esim.detectedAID.isEmpty ? "未检测" : appState.esim.detectedAID)
                if let error = appState.esim.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await appState.refreshESIM() }
                } label: {
                    Label("读取卡片信息", systemImage: "antenna.radiowaves.left.and.right")
                }
                .djGlass()
            }
        }
    }

    private var experimentalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("实验性功能", systemImage: "flask")
                    .font(.headline)
                Text("Profile 的启用、停用、改名与删除已通过 SGP.22 标准指令实现，但这些操作会写入卡片，请务必在确认卡片可恢复后使用。下载新 Profile（需要 SM-DP+ 激活码）将在后续版本提供。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var profilesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Profile", systemImage: "rectangle.stack")
                    .font(.headline)
                if appState.esim.profiles.isEmpty {
                    Text("暂无 Profile 数据。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.esim.profiles) { profile in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name.isEmpty ? "未命名" : profile.name)
                                        .font(.callout.weight(.medium))
                                    Text(profile.iccid)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                                Spacer()
                                StatusBadge(title: profile.state == "enabled" ? "已启用" : "已停用", color: profile.state == "enabled" ? .green : .secondary)
                            }
                            HStack(spacing: 8) {
                                if profile.state == "enabled" {
                                    Button("停用") {
                                        Task { await appState.disableProfile(iccid: profile.iccid) }
                                    }
                                    .djGlass()
                                } else {
                                    Button("启用") {
                                        Task { await appState.enableProfile(iccid: profile.iccid) }
                                    }
                                    .djGlassProminent()
                                }
                                Button("改名") {
                                    profileToRename = profile
                                    renameText = profile.name
                                }
                                .djGlass()
                                Spacer()
                                Button(role: .destructive) {
                                    profileToDelete = profile
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .djGlass()
                                .help("删除 Profile")
                            }
                        }
                        if profile != appState.esim.profiles.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ESIMView()
        .environment(AppState())
}
