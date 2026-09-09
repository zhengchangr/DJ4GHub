import SwiftUI

/// 带 Liquid Glass 效果的内容卡片。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .djGlassPanel(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 状态胶囊。
struct StatusBadge: View {
    var title: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .djGlassPanel(in: Capsule())
    }
}

/// 信号强度条。
struct SignalBars: View {
    var level: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0 ..< 4, id: \.self) { index in
                let active = Double(index + 1) / 4.0 <= level
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: 6 + Double(index) * 4)
            }
        }
        .accessibilityLabel("信号强度")
    }
}

/// 指标行：左侧标签，右侧数值。
struct MetricRow: View {
    var title: String
    var value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospaced(monospaced)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

/// 空状态提示。
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(32)
    }
}
