import SwiftUI
import LimitCore

// MARK: - En aktif saatler

/// Saatlik alışkanlık kartı.
///
/// Kaynak token değil kota: kullanıcıyı durduran şey token sayısı değil,
/// harcanan kota. Ayrıca kota verisi herkeste var, token verisi yalnızca
/// Claude Code veya Desktop kullananlarda.
struct ActiveHoursContent: View {
    let profile: UsageProfile
    /// Ayrıntı sayfasını açar (hafta günü × saat ve saatlik tablo).
    var onShowDetail: () -> Void = {}

    var body: some View {
        // Başlık tabanı y984, tepe etiketinin büyük harf üstü y996: aradaki
        // 12 px → 3,5 pt'yi iki satırın kendi kutu payları zaten dolduruyor,
        // ek boşluk yok.
        VStack(alignment: .leading, spacing: 0) {
            // Sağ üstte "Az … Çok" ölçeği YOK: skalanın yönü zaten şeridin
            // kendisinden okunuyor (soldan sağa günün akışı, koyulaşan renk
            // yoğunluk); başlığın karşısında ikinci bir okuma katmanı açar.
            CardHeader(title: L.t("En Aktif Saatler", "Most Active Hours")) {
                // Ayrıntı yalnızca desen varken: "desen birikiyor" durumunda
                // açılacak bir şey yok.
                if profile.isReliable {
                    DetailLink(action: onShowDetail)
                }
            }

            // `isReliable` (en az 3 gün): tek bir günün verisiyle çizilen
            // harita desen değil gürültü gösteriyor, üstelik kesin bir dille.
            // Eşik `UsageProfile` içinde tanımlı; kart onu burada uygular,
            // yoksa 1 günlük veride bile harita çizer.
            if profile.isReliable {
                HourStream(profile: profile)
            } else {
                // Yeni kurulumda desen henüz yok. Boş bir şerit göstermek
                // yerine ne beklendiğini söylüyor.
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondaryText)
                    Text(L.t("Desen birikiyor", "Building a pattern"))
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: HourStream.height)
            }
        }
    }
}

/// Kart başlığının sağındaki "Ayrıntılar ›" bağlantısı.
private struct DetailLink: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(L.t("Ayrıntılar", "Details"))
                Image(systemName: "chevron.right")
            }
            .font(Typo.badge)
            .foregroundStyle(hovering ? Palette.primaryText : Palette.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L.t("Hafta günü ve saat saat ayrıntı", "Breakdown by weekday and hour"))
    }
}
