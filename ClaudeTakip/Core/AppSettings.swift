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
    var launchAtLogin: Bool = false
    var autoSession: Bool = false
    var autoUpdate: Bool = true
    var darkMode: Bool? = nil
    var aiRecommendation: Bool = true
    var language: String? = nil
    var notes: [Note] = []

    static let defaultSettings = AppSettings()
}
