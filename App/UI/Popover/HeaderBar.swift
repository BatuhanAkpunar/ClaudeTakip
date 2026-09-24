import SwiftUI
import AppKit
import LimitCore

// MARK: - Başlık

struct HeaderBar: View {
    let store: UsageStore
    let onSettings: () -> Void

    var body: some View {
        // Rozet→başlık arası 10: 26 pt'lik rozetin yanında daha geniş bir
        // boşluk orantısız kalır.
        HStack(spacing: 10) {
            AppMark()

            Text("Claude Takip")
                .font(Typo.title)
                .foregroundStyle(Palette.primaryText)

            Spacer(minLength: 6)

            // Sağdaki dört öge TEK bir denetim şeridi: hepsi aynı kart
            // yüzeyinde, aynı 22 pt boyunda, aynı kapsül dilinde; farklı
            // biçimler şeridi dört ayrı şeye böler.
            // Aralık 5: 6 pt'de dört ayrı nesne, 5 pt'de tek bir şerit okunuyor.
            HStack(spacing: 5) {
                ServiceStatusIcon(report: store.serviceStatus)

                // Simge ile yaş etiketi TEK düğme: ikisi aynı şeyi anlatıyor
                // ("veri ne kadar taze" / "şimdi tazele") ama iki ayrı öge
                // olarak dururlarsa yaş etiketi tıklanamaz, simge de neyi
                // yenilediğini söylemez.
                RefreshPill(store: store)

                HeaderButton(systemName: "gearshape", help: L.t("Ayarlar", "Settings"), action: onSettings)

                HeaderButton(systemName: "power", help: L.t("Claude Takip'ten çık", "Quit Claude Takip")) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(height: PopoverLayout.headerHeight)
        // Yatay pay DOĞRUDAN: `outerPadding`'i çıkarıp yeniden ekleyen bir
        // hesap dıştaki `.padding(outerPadding)` ile birbirini götürür ve
        // `outerPadding` değişince başlık kartlarla birlikte kımıldamaz.
        .padding(.horizontal, PopoverLayout.headerInset)
    }
}

/// status.claude.com durumu. Her şey yolundayken de gösterilir, çünkü bir
/// kesinti sırasında "acaba uygulama mı bozuk" sorusunun cevabı burada.
private struct ServiceStatusIcon: View {
    let report: ServiceStatusReport?

    var body: some View {
        // Bulut da diğer düğmelerle aynı yuvarlak yüzeyde: renk durumu
        // söylüyor, biçim onu şeridin bir parçası yapıyor.
        //
        // `Button`, yanındaki üç denetimle aynı. `onTapGesture` KULLANMA: o ne
        // klavyeye ne VoiceOver'a bir şey söyler; simge "resim" diye okunur,
        // durum bilgisi — tek var oluş sebebi — kaybolur, üstelik öğe Tam
        // Klavye Erişimi sırasına hiç girmez.
        Button {
            NSWorkspace.shared.open(Self.statusPage)
        } label: {
            Image(systemName: symbol)
                // 10,5: denetim yüzeyi 22 pt, simge onunla orantılı.
                .font(Typo.headerIcon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .headerCircleChip()
        }
        .buttonStyle(.plain)
        .help(helpText)
        // Durumu yalnızca RENK taşıdığı için ekran okuyucu ve renk körü
        // kullanıcı buradan okuyor.
        .accessibilityLabel(L.t("Servis durumu", "Service status"))
        .accessibilityValue(helpText)
    }

    private static let statusPage = URL(string: "https://status.claude.com")!

    /// Eşik ve gerekçesi: `ServiceStatusReport.staleAfter`.
    private var isStale: Bool {
        report?.isStale() ?? false
    }

    /// Simge HER ZAMAN bulut; durumu RENK söylüyor (yeşil / sarı / kırmızı).
    /// Şekil değiştirmek (üçgen, ünlem) simgeyi her kesintide başka bir şeye
    /// çevirir; aynı yerde aynı nesnenin rengini izlemek daha hızlı okunuyor.
    private var symbol: String {
        // İçi dolu bulut = taze bilgi, içi boş = bilinmiyor ya da bayat.
        isStale || report == nil ? "cloud" : "cloud.fill"
    }

    private var tint: Color {
        if isStale { return Palette.tertiaryText }
        switch report?.status {
        case .operational: return Palette.green
        case .minor: return Palette.warning
        case .major, .critical: return Palette.critical
        default: return Palette.tertiaryText
        }
    }

    private var helpText: String {
        guard let report else { return L.t("Servis durumu okunamadı", "Could not read service status") }
        // Okumanın YAŞI (`checkedAt`) her zaman görünüyor.
        let age = Format.duration(Date().timeIntervalSince(report.checkedAt))
        if isStale {
            return L.t(
                "Servis durumu \(age) önce okundu, güncel olmayabilir · status.claude.com",
                "Service status read \(age) ago, may be out of date · status.claude.com"
            )
        }
        return "\(report.description) · \(age) · status.claude.com"
    }
}

struct HeaderButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typo.headerIcon)
                .foregroundStyle(hovering ? Palette.primaryText : Palette.secondaryText)
                .headerCircleChip(highlighted: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.view, value: hovering)
        .help(help)
    }
}

/// Uygulama işareti: mor zeminli yuvarlak köşeli rozet.
///
/// Çıplak simge başlık metninin yanında ikinci bir "ikon düğmesi" gibi
/// okunur; sağdaki gerçek düğmelerle aynı ağırlıkta durur. Rozet onu bir
/// MARKA öğesine çeviriyor: tıklanabilir değil, uygulamanın kimliği.
private struct AppMark: View {
    var body: some View {
        Image(systemName: "speedometer")
            // 26 pt'lik rozette simge 11 pt; daha büyüğü marka işaretini
            // yuvarlak köşeli kareyi dolduracak kadar büyütür.
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.violetInk)
            .frame(width: PopoverLayout.appMarkSize, height: PopoverLayout.appMarkSize)
            .glassChip(
                RoundedRectangle(cornerRadius: PopoverLayout.appMarkRadius, style: .continuous),
                tint: Palette.violet.opacity(0.30)
            )
    }
}

/// Yenile düğmesi + veri yaşı, tek hap.
private struct RefreshPill: View {
    let store: UsageStore

    @State private var hovering = false
    /// Sonsuz dönüş "Hareketi Azalt" açıkken hiç çalışmamalı.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dataDate: Date { store.freshness?.lastUpdate ?? store.lastRefreshedAt }

    /// Sistem renkleri DEĞİL palet: `.systemYellow` yarı saydam bir hapın
    /// üstünde bu paletteki hiçbir şeye benzemiyor ve `.systemGray` açık temada
    /// okunmuyor.
    ///
    /// Bayatken de `tertiaryText` DEĞİL: o ton dekoratif ve hiçbir zeminde
    /// 4,5:1'e ulaşmıyor. Bayatlık zaten bütün ağacın solmasıyla ve ipucu
    /// metniyle söyleniyor; yaşın kendisi okunabilir kalmalı.
    private var ageTint: Color {
        if case .aging = store.freshness { Palette.warningInk } else { Palette.secondaryText }
    }

    var body: some View {
        Button { store.refreshAll() } label: {
            HStack(spacing: 3.5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.primaryText : Palette.secondaryText)
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    // Dönüş bittiğinde geri SARMIYOR: `.default` ile 360°'den
                    // 0°'ye dönmek çeyrek turu geri alır ve "iptal edildi"
                    // gibi okunur. Aynı süreli ileri geçiş turu tamamlıyor.
                    .animation(
                        reduceMotion ? nil
                            : store.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .linear(duration: 0.2),
                        value: store.isRefreshing
                    )

                Text(Format.age(dataDate))
                    .font(Typo.footnote)
                    .foregroundStyle(ageTint)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: PopoverLayout.headerControlHeight)
            .glassChip(Capsule(style: .continuous), highlighted: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.view, value: hovering)
        .help(helpText)
    }

    private var helpText: String {
        // Bir dakikadan tazeyse `Format.age` "şimdi" döner; "şimdi önce"
        // yazmamak için cümle ayrı.
        var text: String
        if Date().timeIntervalSince(dataDate) < 60 {
            text = L.t("Ekrandaki sayılar az önce alındı. Yenilemek için tıkla.",
                       "The numbers on screen were just fetched. Click to refresh.")
        } else {
            let age = Format.age(dataDate)
            text = L.t("Ekrandaki sayılar \(age) önce alındı. Yenilemek için tıkla.",
                       "The numbers on screen were fetched \(age) ago. Click to refresh.")
        }
        if let freshness = store.freshness, freshness.isStale {
            text += L.t(" Kaynak eskidi: Claude Desktop kapalıyken dosya güncellenmiyor.",
                        " The source is stale: the file does not update while Claude Desktop is closed.")
        }
        return text
    }
}
