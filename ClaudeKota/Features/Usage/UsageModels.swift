import Foundation

struct UsageData: Sendable {
    let fiveHour: Double
    let sevenDay: Double
    var sessionRemaining: Double { 1.0 - fiveHour }
}

enum UsageParseError: Error, LocalizedError {
    case missingFields
    case invalidData

    var errorDescription: String? {
        switch self {
        case .missingFields: "Kullanim verisi eksik"
        case .invalidData: "Gecersiz veri formati"
        }
    }
}

enum UsageResponseParser {
    static func parse(_ data: Data) throws -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHour = json["five_hour"] as? Double,
              let sevenDay = json["seven_day"] as? Double else {
            throw UsageParseError.missingFields
        }
        guard (0...1).contains(fiveHour), (0...1).contains(sevenDay) else {
            throw UsageParseError.invalidData
        }
        return UsageData(fiveHour: fiveHour, sevenDay: sevenDay)
    }
}
