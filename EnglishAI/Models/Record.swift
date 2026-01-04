import Foundation

enum RecordSource: String, Codable {
    case keyboard = "keyboard"
    case wispr = "wispr"
}

struct Record: Identifiable, Codable {
    let id: Int64?
    let timestamp: Date
    let source: RecordSource
    let content: String
    let activeApp: String

    init(id: Int64? = nil, timestamp: Date = Date(), source: RecordSource, content: String, activeApp: String) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.content = content
        self.activeApp = activeApp
    }
}
