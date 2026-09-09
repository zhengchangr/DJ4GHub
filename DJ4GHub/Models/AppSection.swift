import SwiftUI

/// 主导航的各个功能分区。
enum AppSection: String, CaseIterable, Identifiable {
    case status
    case internet
    case sms
    case esim
    case at
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "状态"
        case .internet: "上网"
        case .sms: "短信"
        case .esim: "eSIM"
        case .at: "AT 调试"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .status: "gauge.with.dots.needle.50percent"
        case .internet: "network"
        case .sms: "message.fill"
        case .esim: "simcard.fill"
        case .at: "terminal.fill"
        case .settings: "gearshape.fill"
        }
    }
}
