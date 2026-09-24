import SwiftUI
import LimitCore

/// Günün saatlik yoğunluğu, yatay ısı şeridi olarak.
///
/// 24 hücre soldan sağa, gece yarısından gece yarısına. Yükseklik SABİT,
/// bilgiyi yalnızca renk taşıyor: değişken yükseklikli çubuklar iki kanalı
/// (boy + renk) aynı şeye harcar ve alçak saatler okunmaz hâle gelir.
/// Sabit boylu şeritte göz "günün hangi bandı sıcak" sorusunu tek bakışta
/// cevaplıyor.
struct HourStream: View {
    /// Saatlik profil: `hourly` saat başına ortalama kota tüketimi
    /// (yüzde/gün), `hourSampleDays` her saatin kaç ayrı günde gözlendiği.
    /// Kapsamı düşük saatler zayıf kanıt: uygulama o saatlerde çoğu gün
    /// kapalı (Mac uykuda) ve payda yine tüm günler olduğu için değer
    /// olduğundan düşük çıkıyor. Sayı gizlenmiyor, ipucunda söyleniyor.
    let profile: UsageProfile

    private var hourly: [Double] { profile.hourly }
    private var peak: Double { max(0.001, hourly.max() ?? 0) }

    /// Tepe saatin etiketi ("14:00"); veri yoksa nil.
    private var peakLabel: String? {
        profile.peakHour.map { String(format: "%02d:00", $0) }
    }

    /// İpucu metni: tepe saat, profilin kaç güne dayandığı ve o saatin kaç
    /// günde gözlendiği. Kapsama düşükse sayı olduğundan düşüktür; bunu
    /// saklamak yerine söylüyoruz.
    private var summary: String {
        guard let peakHour = profile.peakHour, let peakLabel else {
            return L.t("Henüz yeterli veri yok", "Not enough data yet")
        }
        let observedDays = profile.observedDays
        let sampleDays = profile.hourSampleDays
        let base = L.t("En yoğun saat \(peakLabel) · \(observedDays) günlük profil",
                       "Peak hour \(peakLabel) · profile from \(observedDays) days")
        guard peakHour < sampleDays.count, observedDays > 0 else { return base }
        let covered = sampleDays[peakHour]
        return base + L.t(" · bu saat \(covered) günde gözlendi",
                          " · this hour observed on \(covered) days")
    }

    // Dikey bütçe puntodan TÜRETİLİYOR. Elle yazılan sabitler punto değişince
    // sessizce yanlış olur ve buradaki hata görünmez: `draw(anchor:)`
    // yazının LAYOUT kutusunu hizalıyor, Canvas da taşan kısmı kırpıyor.
    /// Tepe etiketine ("14:00") ayrılan şerit: tam satır kutusu.
    private static var labelBand: CGFloat { SFMetrics.band(Typo.heatPeakSize) }
    /// Şerit altı → saat ekseni.
    private static let axisGap: CGFloat = 5
    /// Saat ekseni etiketlerine ayrılan şerit.
    ///
    /// Etiket `anchor: .top` ile çiziliyor, yani gereken şey "cap + taban altı
    /// payı" (8,3) değil TAM SATIR KUTUSU (9 × 1,1796 = 10,62); daha azında
    /// rakamların altı 2,3 pt Canvas'ın dışında kalıp kırpılır.
    private static var axisBand: CGFloat { SFMetrics.band(Typo.axisSize) }

    static var height: CGFloat {
        labelBand + PopoverLayout.heatTickGap + PopoverLayout.heatTickHeight
            + PopoverLayout.heatStripHeight + axisGap + axisBand
    }

    var body: some View {
        Canvas { ctx, size in
            let step = size.width / 24
            let gap = step * PopoverLayout.heatGapRatio
            let cellW = step - gap
            let stripY = Self.labelBand + PopoverLayout.heatTickGap + PopoverLayout.heatTickHeight
            let stripH = PopoverLayout.heatStripHeight
            func cellX(_ hour: Int) -> CGFloat { CGFloat(hour) * step }
            func center(_ hour: Int) -> CGFloat { cellX(hour) + cellW / 2 }

            for hour in 0..<24 {
                let rect = CGRect(x: cellX(hour), y: stripY, width: cellW, height: stripH)
                ctx.fill(
                    // Yarıçap hücre genişliğine bağlı: pencere daraldıkça hücre
                    // daralıyor ve sabit yarıçap oranı %31'in üstüne çıkarıp
                    // hücreleri mercimeğe çeviriyor. `Path(roundedRect:)`
                    // yarıçapı kırpmıyor, yalnızca görünüm bozuluyor.
                    Path(roundedRect: rect,
                         cornerRadius: min(PopoverLayout.heatCellRadius, cellW * 0.31),
                         style: .continuous),
                    with: .color(Palette.heat(hourly[hour] / peak))
                )
            }

            // Tepe saat: hücrenin üstünde etiket, etiketten hücreye inen
            // 5,3 pt'lik ince çizgi. Görselde tepe hücresi komşularıyla AYNI
            // boyda; vurgunun tamamını renk, etiket ve çizgi taşıyor.
            if let peakHour = profile.peakHour, let peakLabel {
                let cx = center(peakHour)
                let text = ctx.resolve(
                    Text(peakLabel)
                        .font(Typo.heatPeak)
                        .foregroundStyle(Palette.secondaryText)
                )
                let half = text.measure(in: size).width / 2
                let lx = min(max(cx, half), size.width - half)
                // Satır kutusunun ÜSTÜNDEN hizalanıyor: böylece yazının tepesi
                // her zaman çizim alanının içinde kalıyor.
                ctx.draw(text, at: CGPoint(x: lx, y: 0), anchor: .top)

                let tickTop = Self.labelBand + PopoverLayout.heatTickGap
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: cx, y: tickTop))
                        p.addLine(to: CGPoint(x: cx, y: tickTop + PopoverLayout.heatTickHeight))
                    },
                    with: .color(Palette.heatTick), lineWidth: 0.8
                )
            }

            // Saat ekseni: 00 · 06 · 12 · 18 · 23, hepsi kendi hücresinin
            // merkezinde. Son etiket 23 (24 DEĞİL): saatler 0-23 arası, gün
            // 23:00'te bitiyor, "24" diye bir saat yok. Her etiket iki kenardan
            // da kırpılmayacak biçimde kenetli (uçlardaki 00 ve 23 tuvalin
            // dışına taşmıyor).
            let axisY = stripY + stripH + Self.axisGap
            func axisText(_ value: String) -> GraphicsContext.ResolvedText {
                ctx.resolve(
                    Text(value).font(Typo.axis).monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                )
            }
            for hour in [0, 6, 12, 18, 23] {
                let text = axisText(String(format: "%02d", hour))
                let half = text.measure(in: size).width / 2
                let x = min(max(center(hour), half), size.width - half)
                ctx.draw(text, at: CGPoint(x: x, y: axisY), anchor: .top)
            }
        }
        .frame(height: Self.height)
        .help(summary)
        .accessibilityElement()
        .accessibilityLabel(L.t("En aktif saatler", "Most active hours"))
        .accessibilityValue(summary)
    }
}
