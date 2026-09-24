import SwiftUI
import LimitCore

extension WindowPresentation {
    var icon: String {
        switch kind {
        case .fiveHour: "clock"
        case .sevenDay: "calendar"
        }
    }

    var accent: WindowAccent {
        switch kind {
        case .fiveHour: .fiveHour
        case .sevenDay: .sevenDay
        }
    }
}
