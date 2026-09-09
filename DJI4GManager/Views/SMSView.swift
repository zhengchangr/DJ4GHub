import AppKit
import SwiftUI

struct SMSView: View {
    @Environment(AppState.self) private var appState
    @State private var showComposer = false
    @State private var draftPhone = ""
    @State private var draftText = ""
    @State private var sendError: String?

    var body: some View {
        Group {
            if appState.isConnected {
                messageList
            } else {
                EmptyStateView(
                    icon: appState.isGen2Only ? "simcard" : "message.slash",
                    title: appState.isGen2Only ? "二代模块不支持短信" : "模块未连接",
                    message: appState.isGen2Only
                        ? "二代模块封闭了 USB 管理口，短信收发功能不可用。"
                        : "短信需要模块处于管理模式（USB 模式 0）。"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await appState.refreshSMS() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新短信")

                Button {
                    draftPhone = ""
                    draftText = ""
                    showComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("写短信")
            }
        }
        .sheet(isPresented: $showComposer) { composer }
        .alert("发送失败", isPresented: .init(get: { sendError != nil }, set: { if !$0 { sendError = nil } })) {
            Button("好") { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    private var messageList: some View {
        ScrollView {
            if appState.messages.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "没有短信",
                    message: "点击右上角刷新从模块读取短信。"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appState.messages) { message in
                        messageRow(message)
                            .contextMenu {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.rawHex, forType: .string)
                                } label: {
                                    Label("复制原始数据（排查乱码用）", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    Task { await appState.deleteSMS(at: message.id) }
                                } label: {
                                    Label("从模块删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(18)
            }
        }
    }

    private func messageRow(_ message: SMSMessage) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: message.isIncoming ? "arrow.down.left" : "arrow.up.right")
                        .foregroundStyle(.secondary)
                    Text(message.phoneNumber.isEmpty ? "未知号码" : message.phoneNumber)
                        .font(.callout.weight(.semibold))
                    if let concat = message.concat {
                        Text("第 \(concat.partIndex)/\(concat.totalParts) 段")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.7), in: Capsule())
                    }
                    Spacer()
                    if !message.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                    }
                    if let date = message.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("写短信")
                .font(.title3.weight(.semibold))
            TextField("收件人号码（国际格式 +86…）", text: $draftPhone)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $draftText)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Spacer()
                Button("取消") { showComposer = false }
                    .djGlass()
                Button("发送") {
                    Task { await send() }
                }
                .djGlassProminent()
                .disabled(draftPhone.isEmpty || draftText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func send() async {
        do {
            try await appState.sendSMS(to: draftPhone, text: draftText)
            showComposer = false
        } catch {
            sendError = error.localizedDescription
        }
    }
}

#Preview {
    SMSView()
        .environment(AppState())
}
