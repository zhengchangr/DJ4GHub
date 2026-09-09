import Foundation

struct SMSMessage: Identifiable, Equatable {
    let id: Int
    var phoneNumber: String
    var text: String
    var date: Date?
    var isRead: Bool
    var isIncoming: Bool
}
