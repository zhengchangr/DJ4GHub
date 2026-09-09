import Foundation

/// 当前通话状态（由 AT+CLCC 轮询得到）。
struct PhoneCall: Identifiable, Equatable {
    enum CallState: Equatable {
        case incoming
        case waiting
        case active
    }

    let id = UUID()
    var number: String
    var state: CallState
    var startedAt: Date

    var stateDescription: String {
        switch state {
        case .incoming: "来电"
        case .waiting: "等待接听"
        case .active: "通话中"
        }
    }
}
