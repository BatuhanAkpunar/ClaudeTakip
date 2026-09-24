import SwiftUI
import LimitCore

/// Mockup'taki halka gösterge: kalın iz, yuvarlak uçlu dolgu, ortada yüzde.
struct DonutGauge: View {
    let percent: Double
    let tint: Color
    let track: Color

    private var fraction: Double { min(max(percent, 0), 100) / 100 }

    var body: some View {
        // `stroke` çizgiyi yolun ÜSTÜNE ortalıyor, yani halkanın dış çapı
        // çerçeveyi yarım çizgi kalınlığı kadar aşar: 84 pt'lik çerçeve
        // ekranda 93 pt çizer. `inset` bunu geri alıyor, böylece
        // `donutSize` gerçekten ölçülen DIŞ ÇAP oluyor.
        ZStack {
            Circle()
                .inset(by: PopoverLayout.donutLineWidth / 2)
                .stroke(track, lineWidth: PopoverLayout.donutLineWidth)

            Circle()
                .inset(by: PopoverLayout.donutLineWidth / 2)
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(
                    lineWidth: PopoverLayout.donutLineWidth,
                    lineCap: .round
                ))
                // Trim saat 3 yönünden başlar, gösterge tepeden başlamalı.
                .rotationEffect(.degrees(-90))

            // Görselde sayı tabanı y431, alt yazı tabanı y474 → 43 px → 12,6 pt
            // taban çizgisi aralığı; iki satır arası boşluk 1 pt.
            VStack(spacing: 1) {
                // Yüzde işaretinin yeri dile bağlı: TR "%83", EN "83%".
                Text(Format.percent(percent))
                    .font(Typo.donutValue)
                    .foregroundStyle(Palette.primaryText)
                Text(L.t("kullanıldı", "used"))
                    .font(Typo.donutCaption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(width: PopoverLayout.donutSize, height: PopoverLayout.donutSize)
        // Halkanın dolması ölçülen bir değişimi gösteriyor: sıçrayarak değil
        // ilerleyerek. Sayı da aynı ritimde güncelleniyor.
        .motion(value: percent)
        .accessibilityElement()
        .accessibilityLabel(L.t("Kullanım", "Usage"))
        // Ekrandaki gibi YUVARLANMIŞ: 82,6 görselde 83, okunurken de 83.
        .accessibilityValue(L.t("Yüzde \(Int(percent.rounded()))", "\(Int(percent.rounded())) percent"))
    }
}

/// Hız rozeti: takometre ikonu, çarpan ve isteğe bağlı kısa etiket.
///
/// "günlük ortalamaya göre" gibi uzun bir açıklama yok: her kartta tekrar eder
/// ve bir kez öğrenildikten sonra okunmaz.
struct RateBadge: View {
    let multiplier: Double
    /// Çarpanın ne olduğunu söyleyen kısa etiket ("kullanım hızı"). Grafiğin
    /// başlık satırında duruyor: orada "0,3×" tek başına neyin katı olduğunu
    /// söylemez. nil ise yalnızca simge + sayı.
    var label: String?

    private var tint: Color { Palette.pace(multiplier) }

    var body: some View {
        HStack(spacing: 4) {
            // "speedometer", noktalı iğne varyantından belirgin: 11 pt'de
            // diğerinin kadran noktaları birbirine giriyor ve gri bir leke oluyor.
            // Hız, zaman etiketleriyle aynı satırda ve aynı boyda: ikisi de
            // grafiğin altındaki okuma şeridi, farklı puntolar o şeridi
            // bozar.
            //
            // Görselde takometre 44×30 px → 12,9 × 8,8 pt.
            LucideGauge()
                .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                // 11,5 (görseldeki 12,9 değil): 12,9'da bu glif grafiğin başlık
                // satırının en uzun ögesi olur ve satırın boyunu O belirler.
                // 11,5'te boyu yazı belirliyor. `LucideGauge` 24 birimlik ızgarayı
                // min(width, height)'e ölçeklediği için şekil etkilenmiyor.
                .frame(width: 11.5, height: 11.5)
            Text(Format.multiplier(multiplier))
                .font(Typo.rateValue)

            if let label {
                // Etiket ikincil renkte: hız tonu (griden kırmızıya) SAYIYA
                // ait bir uyarı, açıklama metnine değil. Tek satır ve
                // kırpılmaz: sarınca grafiğin başlık satırı iki kata çıkar.
                // Font `rateValue` DEĞİL `footnote`: ikisi de 10 pt ama
                // rateValue medium, yani "1,25×" ile "kullanım hızı"
                // ağırlıkla ayrılıyor; renk zaten hız tonuna ayrılmış.
                Text(label)
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(tint)
        .help(multiplier >= 1
              ? L.t("Bu gidişle kotanın \(Format.multiplier(multiplier)) katını kullanacaksın: sıfırlanmadan önce dolar.",
                    "At this pace you'd use \(Format.multiplier(multiplier)) your quota: it runs out before the reset.")
              : L.t("Bu gidişle sıfırlanmada kotanın \(Format.multiplier(multiplier)) katı kullanılmış olur. 1'in üstü, sıfırlanmadan dolmak demek.",
                    "At this pace you'll have used \(Format.multiplier(multiplier)) your quota by the reset. Above 1 means it runs out first."))
        .accessibilityLabel(L.t("Kullanım hızı", "Pace"))
        .accessibilityValue(L.t("Kotanın \(Format.multiplier(multiplier)) katı",
                                "\(Format.multiplier(multiplier)) of the quota"))
    }
}

struct SlimBar: View {
    let percent: Double
    let tint: Color
    let track: Color

    var body: some View {
        GeometryReader { geometry in
            let filled = geometry.size.width * min(max(percent, 0), 100) / 100
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(track)
                Capsule(style: .continuous)
                    .fill(tint)
                    // Sıfır GERÇEKTEN sıfır: alt sınır yalnızca kullanım
                    // varken uygulanıyor. `max(filled, 6)` koşulsuz olursa %0
                    // kullanımda da 6 pt dolu çubuk çizilir ve cüzdanı hiç
                    // kullanmamış biri "bir şey harcamışım" diye okur.
                    .frame(width: percent > 0 ? max(filled, 6) : 0)
            }
        }
        .frame(height: PopoverLayout.slimBarHeight)
        .motion(value: percent)
    }
}

/// Lucide'ın `gauge` ikonu.
///
/// SF Symbols'ta karşılığı yok; Lucide'ın 24×24 kılavuzundaki iki yolu birebir
/// çiziyor: 12,12 merkezli 10 yarıçaplı üst yay ve merkezden sağ üste giden
/// ibre. Rengi dışarıdan geliyor, böylece hız durumuna göre renkleniyor.
private struct LucideGauge: Shape {
    func path(in rect: CGRect) -> Path {
        // Lucide kılavuzu 24 birim; çizim alanına ölçekleniyor.
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        // M3.34 19 a10 10 0 1 1 17.32 0  (üst yarım yay)
        path.addArc(
            center: point(12, 12),
            radius: 10 * scale,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        // m12 14 4-4  (ibre)
        path.move(to: point(12, 14))
        path.addLine(to: point(16, 10))
        return path
    }
}
