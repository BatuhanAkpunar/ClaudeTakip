import Foundation
import AppKit

enum StatusResponseParser {
    static func parse(_ data: Data) throws -> SystemStatus {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let indicator = status["indicator"] as? String else {
            throw UsageParseError.missingFields
        }
        switch indicator {
        case "none": return .operational
        case "major", "critical": return .major
        case "maintenance": return .maintenance
        default: return .degraded
        }
    }
}

@MainActor
final class StatusService {
    private let appState: AppState
    private var pollingTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: TimingConstants.statusPollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchStatus()
            }
        }
        Task { await fetchStatus() }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func openStatusPage() {
        if let url = URL(string: APIConstants.statusWebURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func fetchStatus() async {
        guard let url = URL(string: APIConstants.statusURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            appState.claudeSystemStatus = try StatusResponseParser.parse(data)
        } catch {
            // If status cannot be fetched, keep current state
        }
    }
}
