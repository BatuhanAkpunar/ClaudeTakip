import SwiftUI
import LimitCore

// MARK: - Fable

struct FableContent: View {
    /// Yüzde ve bu yüzdenin ÖLÇÜM mü TAHMİN mi olduğu.
    let usage: (percent: Double, isEstimate: Bool)?
    /// Fable kotasının sıfırlanma anı.
    let resetsAt: Date?

    private var percent: Double { usage?.percent ?? 0 }
    private var isEstimate: Bool { usage?.isEstimate ?? true }

    var body: some View {
        // Ölçülen taban çizgileri: başlık y682, "%4" y765, çubuk 788-811,
        // tarih y858. Aradaki paylar satır kutusu farkları çıkarılarak bulundu.
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Fable")

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Tahminde "~": sayının ölçüm olmadığı tek karakterle
                // söyleniyor. Sunucudan gerçek kota gelince işaret düşüyor.
                if isEstimate {
                    Text("~")
                        .font(Typo.heroValue)
                        .foregroundStyle(Palette.secondaryText)
                }
                Text(Format.percent(percent))
                    .font(Typo.heroValue)
                    .foregroundStyle(Palette.primaryText)
                Text(L.t("kullanıldı", "used"))
                    .font(Typo.heroLabel)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            // Bölüm etiketi ile sayı arası SABİT: ikisi tek öbek okunmalı.
            .padding(.top, PopoverLayout.titleToHeroGap)
            .motion(value: percent)

            SlimBar(percent: percent, tint: Palette.violet, track: Palette.violetTrack)
                .padding(.top, PopoverLayout.heroToBarGap)

            // Esnek boşluk BURADA, başlığın altında değil.
            //
            // İki kart aynı boyda ve Fable doğal hâlinde ~27 pt daha kısa;
            // fazlalık bir yere düşmek zorunda. Başlıkla sayı arasına
            // düştüğünde kartın en görünür yerinde kocaman bir delik açar.
            // Altta ise tarih satırını kartın dibine yaslıyor, yani iki kartın
            // tarih satırı da hizalanıyor.
            Spacer(minLength: PopoverLayout.barToMetaGap)

            if let resetsAt {
                let renewal = Format.resetSentence(resetsAt, includeTime: false)
                MetaLine(symbol: "calendar",
                         text: renewal,
                         shortText: Format.shortDate(resetsAt))
                    .help(L.t("Yenilenme: \(renewal)",
                              "Renewal: \(renewal)"))
            }
        }
        .help(isEstimate
            ? L.t("Tahmini: sunucu Fable kotasını vermiyor, değer yerel token payından hesaplanıyor.",
                  "Estimated: the server is not reporting a Fable quota, so this is derived from the local token share.")
            : L.t("Fable modelinin haftalık kotası, doğrudan sunucudan.",
                  "Weekly quota for the Fable model, straight from the server."))
    }
}
