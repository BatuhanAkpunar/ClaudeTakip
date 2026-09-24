import SwiftUI
import LimitCore

/// Ekstra kullanım cüzdanı.
///
/// Fable kartının yanındaki GENİŞ kart. Kahraman sayı KALAN BAKİYE: para
/// bittiğinde iş durur, kullanıcının asıl sorusu odur. Yüzde en az işe yarayan
/// sayı olduğu için ikinci plana atıldı. Tüm durum mantığı `WalletPresentation`
/// içinde; burası yalnızca çiziyor.
struct WalletContent: View {
    let state: WalletState

    var body: some View {
        let model = WalletPresentation.make(state)
        // Görseldeki kurulum: solda kahraman sayı, SAĞDA iki "etiket + rozet"
        // satırı (Kredi Kullanımı · Oto-yenileme), altta yenilenme tarihi.
        // Kart bu yüzden Fable'dan geniş (190 pt / 148 pt).
        return VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: L.t("Cüzdan", "Wallet"))

            // SOLDA kahraman sayı, SAĞDA iki "etiket + rozet" satırı.
            //
            // Hizalama `.center` DEĞİL `.top`: rozet sütunu (35 pt) kahraman
            // sayıdan (23,6 pt) uzun olduğu için ortalamak sayıyı 5,7 pt aşağı
            // iter ve "$9,18" ile yandaki kartın "%4"ü aynı satırda
            // görünmez. İki kartın kahraman sayısı aynı taban
            // çizgisinde: ikisi de bölüm etiketinden `titleToHeroGap` kadar
            // aşağıda başlıyor.
            HStack(alignment: .top, spacing: 6) {
                if let hero = model.heroValue {
                    // Kalan bakiyede etiket YOK: "$9,18"in bakiye olduğunu
                    // kartın başlığı ve yanındaki "Kredi Kullanımı" satırı
                    // zaten söylüyor. Ama kahraman HARCANAN tutarsa etiket
                    // şart ("harcandı"); yoksa harcanan bakiye diye okunur.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(hero)
                            .font(Typo.heroValue)
                            .foregroundStyle(Palette.primaryText)
                            .fixedSize()
                        if let label = model.heroLabel {
                            Text(label)
                                .font(Typo.heroLabel)
                                .foregroundStyle(Palette.secondaryText)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .motion(value: hero)
                }

                VStack(alignment: .trailing, spacing: PopoverLayout.pillRowGap) {
                    LabeledPill(label: L.t("Kredi Kullanımı", "Extra usage"),
                                shortLabel: L.t("Kredi", "Usage"),
                                text: model.status,
                                fill: model.statusTone.pillFill,
                                ink: model.statusTone.pillInk)
                    if let autoReload = model.autoReload {
                        let tone: WalletPresentation.Tone = autoReload ? .calm : .muted
                        LabeledPill(
                            label: L.t("Oto Yenileme", "Auto-reload"),
                            shortLabel: L.t("Oto", "Auto"),
                            text: autoReload ? WalletPresentation.onText : WalletPresentation.offText,
                            fill: tone.pillFill,
                            ink: tone.pillInk
                        )
                        .help(L.t("Otomatik bakiye yükleme", "Automatic balance top-up"))
                    }
                }
                // Buraya `.fixedSize()` EKLEME: sütuna ÖLÇÜSÜZ bir öneri
                // verir ve `ViewThatFits` ölçüsüz öneride HER adayı sığmış
                // sayıp ilkini seçer — yani `LabeledPill`in "Kredi Kullanımı
                // → Kredi" yedeği hiç çalışmaz, "Tavan doldu" hâlinde satır
                // kartın dışına taşar. `Spacer` da EKLEME: iki sonsuz esnek
                // çocuk varken HStack artan yeri ikiye böler ve sütuna yalnız
                // yarısı önerilir. Kahramandan artan genişliğin tamamı öneri,
                // hizayı `alignment` taşıyor.
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // Bölüm etiketi ile içerik arası SABİT: Fable ile aynı kural.
            .padding(.top, PopoverLayout.titleToHeroGap)

            if let fraction = model.barFraction {
                SlimBar(percent: fraction * 100, tint: model.barTone.barColor,
                        track: model.barTone.barColor.opacity(0.16))
                    .padding(.top, PopoverLayout.heroToBarGap)
            }

            if let detail = model.detail {
                Text(detail)
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .padding(.top, 3)
            }

            if let amounts = model.amounts {
                FootnoteText(text: amounts)
                    .padding(.top, 3)
            }

            // Esnek boşluk ALTTA, başlığın dibinde değil — Fable ile aynı
            // kural. İki kart eşit boyda ve hangisinin kısa kaldığı DURUMA
            // bağlı: ekstra kullanım kapalı ve bakiye yokken Cüzdan tek rozet
            // satırına iniyor ve kısa olan O oluyor. Fazlalık başlığın dibine
            // düştüğünde "CÜZDAN" ile ilk satır arasında ~22 pt delik açar.
            Spacer(minLength: 0)

            if let renewal = model.renewalDate {
                MetaLine(symbol: "calendar", text: renewal)
                    // +1 pt: Cüzdan'da tarihin üstündeki öge bir ROZET, yani
                    // yuvarlak uçlu bir kapsül. Kapsülün eğrilen alt kenarı
                    // Fable'daki düz çubuktan bir tık yukarıda okunuyor;
                    // ölçüldü, iki kartta da üst/alt payı 11 pt'ye getiriyor.
                    .padding(.top, PopoverLayout.barToMetaGap + 1)
                    .help(L.t("Bakiyenin yenilenme tarihi", "When the balance renews"))
            }
        }
        .help(model.help)
    }
}

extension WalletPresentation.Tone {
    var barColor: Color {
        switch self {
        case .calm: return Palette.blue
        case .warn: return Palette.warning
        case .danger: return Palette.critical
        case .muted: return Palette.secondaryText
        }
    }

    /// Rozet zemini: görselde "Açık" #E2F1E5, "Kapalı" #E8ECEF. Uyarı ve
    /// tehlike hâlleri görselde yok, sistem renginin soluk hâline düşüyorlar.
    var pillFill: Color {
        switch self {
        case .calm: return Palette.greenSoft
        case .warn: return Palette.warning.opacity(0.16)
        case .danger: return Palette.critical.opacity(0.16)
        case .muted: return Palette.neutralPill
        }
    }

    /// Rozet metni: "Açık" #2A7955, "Kapalı" #393E48.
    var pillInk: Color {
        switch self {
        case .calm: return Palette.greenInk
        case .warn: return Palette.warningInk
        case .danger: return Palette.criticalInk
        case .muted: return Palette.primaryText
        }
    }
}
