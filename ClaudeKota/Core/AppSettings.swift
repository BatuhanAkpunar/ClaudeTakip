import Foundation

struct Note: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, content: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }
}

struct AppSettings: Codable, Sendable {
    var fastConsumptionAlert: Bool = true
    var criticalThresholdAlert: Bool = true
    var resetNotification: Bool = true
    var soundEnabled: Bool = false
    var launchAtLogin: Bool = false
    var autoSession: Bool = false
    var darkMode: Bool? = nil
    var notes: [Note] = []

    static let defaultSettings = AppSettings()
}
