import SwiftUI
import LimitCore

#if DEBUG
struct WalletGallery: View {
    static let cases: [(String, WalletState)] = [
        ("Harcanıyor", WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 32,
            monthlyLimit: 50, usedCredits: 16.20, remainingBalance: 33.80, currency: "USD",
            autoReloadEnabled: true)),
        ("Tavan aşıldı", WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 100,
            monthlyLimit: 50, usedCredits: 62.40, remainingBalance: 0, currency: "USD",
            autoReloadEnabled: true)),
        ("Hazır", WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 0,
            monthlyLimit: 50, usedCredits: 0, remainingBalance: 50, currency: "USD",
            autoReloadEnabled: false)),
        ("Tavan doldu", WalletState(isEnabled: false, disabledReason: nil, consumedPercent: 100, spendLimitReached: true,
            monthlyLimit: 2, usedCredits: 13.83, remainingBalance: 9.18, currency: "USD",
            autoReloadEnabled: false)),
        ("Uyuyan bakiye", WalletState(isEnabled: false, disabledReason: nil, consumedPercent: nil,
            monthlyLimit: nil, usedCredits: nil, remainingBalance: 34.50, currency: "USD",
            autoReloadEnabled: false)),
        ("Yalnız yüzde", WalletState(isEnabled: true, disabledReason: nil, consumedPercent: 100)),
        ("Kapalı", WalletState(isEnabled: false, disabledReason: "ekstra kullanım kapalı",
            consumedPercent: nil)),
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(Self.cases.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    MetricCard(width: PopoverLayout.wideCardWidth) {
                        WalletContent(state: item.1)
                    }
                    .frame(width: PopoverLayout.wideCardWidth, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: PopoverLayout.wideCardWidth + 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
