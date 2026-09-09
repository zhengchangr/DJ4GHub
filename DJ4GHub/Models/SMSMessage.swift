import Foundation

/// 长短信（超长短信被拆成多段）的分片信息。
struct SMSConcatInfo: Equatable {
    let reference: Int
    let totalParts: Int
    /// 从 1 开始计数的第几段。
    let partIndex: Int
}

struct SMSMessage: Identifiable, Equatable {
    let id: Int
    var phoneNumber: String
    var text: String
    var date: Date?
    var isRead: Bool
    var isIncoming: Bool
    /// 长短信分片信息（普通短信为 nil）。
    var concat: SMSConcatInfo? = nil
    /// 模块返回的原始 PDU 十六进制（用于排查乱码）。
    var rawHex = ""
}
