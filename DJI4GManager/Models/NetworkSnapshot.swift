import Foundation

struct ByteCounters: Equatable {
    var rx: UInt64
    var tx: UInt64
}

struct MacInterfaceInfo: Equatable {
    var name: String
    var status: String
    var ipv4: String
}

struct NetworkSnapshot: Equatable {
    var interfaces: [MacInterfaceInfo] = []
    var defaultRouteInterface = ""
    var defaultGateway = ""
    var counters: [String: ByteCounters] = [:]
    var activeInterface = ""
    var isAvailable = false
    var usingModuleAsDefault = false
    var sessionRX: UInt64 = 0
    var sessionTX: UInt64 = 0
    var pathStatus = "未检测"

    var sessionTotal: UInt64 { sessionRX + sessionTX }
}

/// 系统网络服务（对应“系统设置 → 网络”里的服务条目）。
struct NetworkServiceInfo: Equatable {
    var name: String
    var port: String
    var device: String
}
