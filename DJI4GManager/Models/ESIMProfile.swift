import Foundation

/// eSIM / eUICC 卡片状态。
struct ESIMState: Equatable {
    var eid = ""
    var detectedAID = ""
    var profiles: [ESIMProfile] = []
    var isExperimental = true
    var lastError: String?
}

struct ESIMProfile: Identifiable, Equatable {
    var id: String { iccid }
    var iccid: String
    var name: String
    var state: String
    var serviceProvider: String?
    var isDefault = false
}
