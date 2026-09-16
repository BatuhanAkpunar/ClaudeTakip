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
        // çerçeveyi yarım çizgi kalınlığı kadar aşıyordu: 84 pt'lik çerçeve
        // ekranda 93 pt çiziyordu. `inset` bunu geri alıyor, böylece
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
                Text(L.t("%\(Int(percent.rounded()))", "\(Int(percent.rounded()))%"))
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
        .accessibilityValue(L.t("Yüzde \(Int(percent))", "\(Int(percent)) percent"))
    }
}

/// Hız rozeti: takometre ikonu ve çarpan, başka hiçbir şey.
///
/// Açıklama metni kaldırıldı: "günlük ortalamaya göre" her kartta tekrar eden
/// ve bir kez öğrenildikten sonra okunmayan bir satırdı. Yerini grafiğe bıraktı.
struct RateBadge: View {
    let multiplier: Double
    /// Çarpanın ne olduğunu söyleyen kısa etiket ("kullanım hızı"). Grafiğin
    /// başlık satırında duruyor: orada "0,3×" tek başına neyin katı olduğunu
    /// söylemiyordu. nil ise yalnızca simge + sayı.
    var label: String?

    private var tint: Color { Palette.pace(multiplier) }

    var body: some View {
        HStack(spacing: 4) {
            // "speedometer", noktalı iğne varyantından belirgin: 11 pt'de
            // diğerinin kadran noktaları birbirine giriyor ve gri bir leke oluyor.
            // Hız, zaman etiketleriyle aynı satırda ve aynı boyda: ikisi de
            // grafiğin altındaki okuma şeridi, farklı puntolar o şeridi
            // bozuyordu.
            //
            // Görselde takometre 44×30 px → 12,9 × 8,8 pt.
            LucideGauge()
                .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: 12.9, height: 12.9)
            Text(Format.multiplier(multiplier))
                .font(Typo.rateValue)

            if let label {
                // Etiket ikincil renkte: hız tonu (griden kırmızıya) SAYIYA
                // ait bir uyarı, açıklama metnine değil. Tek satır ve
                // kırpılmaz: sarınca grafiğin başlık satırı iki kata çıkıyordu.
                Text(label)
                    .font(Typo.rateValue)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(tint)
        .help(L.t("Bu pencere türündeki geçmiş ortalama hızın katı",
                  "Multiple of your past average pace for this window type"))
        .accessibilityLabel(L.t("Hız", "Pace"))
        .accessibilityValue(L.t("Ortalamanın \(Format.multiplier(multiplier)) katı",
                                "\(Format.multiplier(multiplier)) the average"))
    }
}

/// Mockup'taki alan grafiği: gradyan dolgulu geçmiş eğrisi ve kesikli projeksiyon.
///
/// Y ekseni sabit 0-100. Otomatik ölçek, yüzde ikilik bir dalgalanmayı yüzde
/// doksanlık bir tırmanış gibi gösterirdi.
struct AreaChart: View {
    let history: [SparkPoint]
    let projected: Double
    /// Eğrinin rengi. Görselde halkadan bir tık koyu (#D98D72 / #DD9D85).
    let tint: Color
    /// Eğrinin altındaki düz dolgu. Görselde gradyan YOK: tek ton (#FDF2EE).
    var areaFill: Color = .clear
    /// Gelecek tahmin eğrisi (x: pencere konumu, y: kullanım%). Boşsa tahmin
    /// çizilmiyor.
    var forecast: [SparkPoint] = []
    /// Tahmin pencere kapanmadan %100'e varıyor mu.
    var willOverrun: Bool = false

    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(
                    x: size.width * min(max(x, 0), 1),
                    y: size.height * (1 - min(max(y, 0), 100) / 100)
                )
            }

            // Ölçek etiketlerinin karşılığı olan çok soluk yatay çizgiler.
            // Etiket olup çizgi olmayınca %50 nereye denk geliyor okunmuyordu.
            for step in YAxisScale.steps {
                let y = point(0, Double(step)).y.rounded() + 0.5
                // Görselde ölçek çizgileri NOKTALI ve çok soluk.
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(Palette.tertiaryText.opacity(0.34)),
                    style: StrokeStyle(lineWidth: 0.75, dash: [1.2, 2.4])
                )
            }

            guard history.count > 1 else { return }

            var line = Path()
            line.move(to: point(history[0].x, history[0].y))
            for item in history.dropFirst() {
                line.addLine(to: point(item.x, item.y))
            }

            if let first = history.first, let last = history.last {
                var area = line
                area.addLine(to: CGPoint(x: point(last.x, 0).x, y: size.height))
                area.addLine(to: CGPoint(x: point(first.x, 0).x, y: size.height))
                area.closeSubpath()
                // Görselde alan dolgusu DÜZ tek ton; gradyan yok.
                context.fill(area, with: .color(areaFill))
            }

            // Eğri kalınlığı görselde 8 px → 2,3 pt.
            context.stroke(line, with: .color(tint), style: StrokeStyle(
                lineWidth: 2.3, lineCap: .round, lineJoin: .round
            ))

            // Projeksiyon ayrı bir alan değil, eğrinin kesikli devamı.
            //
            // KESİKLİ olması "bu ölçüm değil tahmin" demeye zaten yetiyor;
            // rengin işi bu değil. Kırmızı bir UYARI ve yalnızca gerçek bir
            // aşım öngörüldüğünde çıkıyor. Önceden her tahmin kırmızıydı ve
            // "5 saatte %100'e gelmeyeceksin" diyen bir grafik bile alarm
            // rengiyle çiziliyordu.
            guard history.last != nil else { return }
            // Tahmin YALNIZCA gerçek bir aşım öngörüldüğünde çiziliyor.
            //
            // Sıfırlanmaya kadar %100'e varmıyorsan gösterilecek bir uyarı yok;
            // eğri çizmek "şuraya kadar gideceksin" diyen gereksiz bir iddia
            // oluyor. Kart o durumda yalnızca ölçülmüş eğriyi gösteriyor.
            guard willOverrun, forecast.count >= 2 else { return }

            // Tahmin eğrisi, %100'ü kestiği noktaya kadar çiziliyor. Kesikli
            // olması "ölçüm değil tahmin" diyor; eğrinin şekli (haftalıkta düz
            // değil, kullanıcının geçmiş ritmine göre bükülü) modeli anlatıyor.
            // İlk nokta zaten tavandaysa çizilecek bir gelecek yok. Bu dal
            // olmadan aşağıdaki döngü i = 0 için `forecast[-1]` okuyup
            // çöküyordu: kullanım %100'e vardığında eğrinin ilk noktası tam
            // 100 oluyor ve çökme tam da kullanıcının limite bakmak için
            // popover'ı açtığı anda gerçekleşiyordu.
            guard forecast[0].y < 100 else { return }

            var path = Path()
            var started = false
            var endPoint: CGPoint?
            for i in forecast.indices {
                let p = forecast[i]
                if p.y >= 100, i > 0 {
                    // %100 çizginin bu noktayla bir önceki arasında kesiliyor.
                    let prev = forecast[i - 1]
                    let span = p.y - prev.y
                    let frac = span > 0 ? (100 - prev.y) / span : 0
                    let cutX = prev.x + (p.x - prev.x) * frac
                    let pt = point(cutX, 100)
                    if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
                    endPoint = pt
                    break
                }
                let pt = point(p.x, p.y)
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
                endPoint = pt
            }

            context.stroke(path, with: .color(Palette.projection), style: StrokeStyle(
                lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [3, 3]
            ))

            // İşaretçi tahmin eğrisinin bittiği yerde (aşım anı). Tam kenara
            // dayanıyorsa hafif içeri alınıyor.
            if let raw = endPoint {
                let end = CGPoint(
                    x: min(raw.x, size.width - 4),
                    y: min(max(raw.y, 4), size.height - 4)
                )
                let dot = CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)
                context.stroke(Path(ellipseIn: dot), with: .color(Palette.projection), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
        // Grafiğin yeniden çizilmesi sekme değişiminde ve her veri turunda
        // oluyor; ani takas iki ayrı grafik varmış gibi görünüyordu.
        .motion(value: projected)
    }
}

/// Günün saatlik yoğunluğu, yatay ısı şeridi olarak.
///
/// 24 hücre soldan sağa, gece yarısından gece yarısına. Yükseklik SABİT,
/// bilgiyi yalnızca renk taşıyor: değişken yükseklikli çubuklar iki kanalı
/// (boy + renk) aynı şeye harcıyor ve alçak saatler okunmaz hâle geliyordu.
/// Sabit boylu şeritte göz "günün hangi bandı sıcak" sorusunu tek bakışta
/// cevaplıyor.
struct HourStream: View {
    /// Saat başına ortalama kota tüketimi, yüzde/gün.
    let hourly: [Double]
    /// Her saatin kaç ayrı günde gözlendiği. Kapsamı düşük saatler zayıf kanıt:
    /// uygulama o saatlerde çoğu gün kapalıydı (Mac uykuda) ve payda yine tüm
    /// günler olduğu için değer olduğundan düşük çıkıyor. Sayı gizlenmiyor,
    /// ipucunda söyleniyor.
    var sampleDays: [Int] = []
    var observedDays: Int = 0

    private var peak: Double { max(0.001, hourly.max() ?? 0) }
    private var peakHour: Int? {
        guard let maximum = hourly.max(), maximum > 0 else { return nil }
        return hourly.firstIndex(of: maximum)
    }

    /// İpucu metni: tepe saat, profilin kaç güne dayandığı ve o saatin kaç
    /// günde gözlendiği. Kapsama düşükse sayı olduğundan düşüktür; bunu
    /// saklamak yerine söylüyoruz.
    private var summary: String {
        guard let peakHour else {
            return L.t("Henüz yeterli veri yok", "Not enough data yet")
        }
        let base = L.t("En yoğun saat \(String(format: "%02d:00", peakHour)) · \(observedDays) günlük profil",
                       "Peak hour \(String(format: "%02d:00", peakHour)) · profile from \(observedDays) days")
        guard peakHour < sampleDays.count, observedDays > 0 else { return base }
        let covered = sampleDays[peakHour]
        return base + L.t(" · bu saat \(covered) günde gözlendi",
                          " · this hour observed on \(covered) days")
    }

    // Dikey bütçe ÖLÇÜLDÜ: tepe etiketi tabanı y1011, işaret çizgisi
    // y1019-1037, şerit y1036-1105, saat ekseni y1129-1145.
    /// Tepe etiketine ayrılan şerit: yazının TAM SATIR KUTUSU (9 pt × 1,1796).
    ///
    /// Eskiden yalnızca büyük harf yüksekliği kadardı (6,7 pt) ve etiket
    /// taban çizgisine göre yerleştiriliyordu; harflerin tepesi Canvas'ın
    /// üstünde kalıyor, yani "10:00" yazısının üstü kırpılıyordu.
    private static let labelBand: CGFloat = 10.7
    /// Şerit altı → saat ekseni büyük harf üstü.
    private static let axisGap: CGFloat = 7
    /// Eksen yazısının büyük harf yüksekliği + taban altı payı (9 pt).
    ///
    /// Bu değer EKSİK OLURSA saat etiketleri Canvas'ın dışında kalıyor ve
    /// hiç çizilmiyor: 9 pt'lik yazının cap'i 6,34, taban altı payı 1,90.
    private static let axisBand: CGFloat = 8.3

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
                    Path(roundedRect: rect, cornerRadius: PopoverLayout.heatCellRadius,
                         style: .continuous),
                    with: .color(Palette.heat(hourly[hour] / peak))
                )
            }

            // Tepe saat: hücrenin üstünde etiket, etiketten hücreye inen
            // 5,3 pt'lik ince çizgi. Görselde tepe hücresi komşularıyla AYNI
            // boyda; vurgunun tamamını renk, etiket ve çizgi taşıyor.
            if let peakHour {
                let cx = center(peakHour)
                let text = ctx.resolve(
                    Text(String(format: "%02d:00", peakHour))
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

            // Saat ekseni: 00 · 06 · 12 · 18 hücre merkezlerinde, 24 sağ kenarda.
            let axisY = stripY + stripH + Self.axisGap
            func axisText(_ value: String) -> GraphicsContext.ResolvedText {
                ctx.resolve(
                    Text(value).font(Typo.axis).monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                )
            }
            for hour in [0, 6, 12, 18] {
                let text = axisText(String(format: "%02d", hour))
                let half = text.measure(in: size).width / 2
                ctx.draw(text, at: CGPoint(x: max(center(hour), half), y: axisY), anchor: .top)
            }
            ctx.draw(axisText("24"), at: CGPoint(x: size.width, y: axisY), anchor: .topTrailing)
        }
        .frame(height: Self.height)
        .help(summary)
        .accessibilityElement()
        .accessibilityLabel(L.t("En aktif saatler", "Most active hours"))
        .accessibilityValue(summary)
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
                    // varken uygulanıyor. `max(filled, 6)` koşulsuzken %0
                    // kullanımda da 6 pt dolu çubuk çiziliyordu ve cüzdanı hiç
                    // kullanmamış biri "bir şey harcamışım" diye okuyordu.
                    .frame(width: percent > 0 ? max(filled, 6) : 0)
            }
        }
        .frame(height: PopoverLayout.slimBarHeight)
        .motion(value: percent)
    }
}

/// Grafik altındaki zaman ekseni etiketleri.
/// Eksen fontu: işaret sayısına göre.
///
/// Slot başına düşen genişlik sabit (~205 pt / işaret sayısı); haftalık eksende
/// 8 işaret olunca 10 pt fontla "29 Ağu" gibi çift kelimeli bir etiket
/// komşusuna 2,5 pt taşıyordu. 8,5 pt ölçülerek seçildi, 3 pt güvenli boşluk
/// bırakıyor. Aynı font hem x hem y ekseninde kullanılıyor: iki eksenin farklı
/// puntoda olması grafiği düzensiz gösteriyordu.
func axisFont(tickCount: Int) -> Font {
    // Görselde x ekseni cap 17 px → 7,1 pt, y ekseni 16 px → 6,6 pt. Aradaki
    // fark ölçüm gürültüsü sınırında; ikisi de tek değerde birleşti.
    _ = tickCount
    return Typo.axis
}

struct AxisLabels: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(axisFont(tickCount: labels.count))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: alignment(index))
            }
        }
    }

    private func alignment(_ index: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == labels.count - 1 { return .trailing }
        return .center
    }
}

/// Grafiğin solundaki sabit 0-100 ölçeği.
///
/// Y ekseni asla otomatik ölçeklenmiyor, dolayısıyla ölçek bilginin kendisi:
/// eğrinin yüksekliği doğrudan yüzde olarak okunabiliyor.
///
/// Üç kademe: 0, 50, 100. Beş kademe 74 pt'lik bir grafikte etiketleri
/// birbirine yaklaştırıyor ve dört soluk çizgi eğriyle yarışıyordu; yarı
/// nokta zaten okumanın gerektirdiği tek ara referans.
struct YAxisScale: View {
    static let steps = [100, 50, 0]

    /// X ekseniyle aynı işaret sayısı bilgisi: iki eksen aynı fontta çizilsin.
    var tickCount: Int = 5

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, value in
                Text("\(value)")
                if index < Self.steps.count - 1 { Spacer(minLength: 0) }
            }
        }
        .font(axisFont(tickCount: tickCount))
        .monospacedDigit()
        .foregroundStyle(Palette.secondaryText)
        .frame(width: PopoverLayout.yAxisWidth, height: PopoverLayout.chartHeight, alignment: .trailing)
        .accessibilityHidden(true)
    }
}


/// Lucide'ın `gauge` ikonu.
///
/// SF Symbols'ta karşılığı yok; Lucide'ın 24×24 kılavuzundaki iki yolu birebir
/// çiziyor: 12,12 merkezli 10 yarıçaplı üst yay ve merkezden sağ üste giden
/// ibre. Rengi dışarıdan geliyor, böylece hız durumuna göre renkleniyor.
struct LucideGauge: Shape {
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
