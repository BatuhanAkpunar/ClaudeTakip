import SwiftUI
import LimitCore

/// Mockup'taki alan grafiği: düz (gradyansız) dolgulu geçmiş eğrisi ve kesikli projeksiyon.
///
/// Y ekseni sabit 0-100. Otomatik ölçek, yüzde ikilik bir dalgalanmayı yüzde
/// doksanlık bir tırmanış gibi gösterirdi.
struct AreaChart: View {
    let history: [SparkPoint]
    let projected: Double
    /// Grafik eğrisi: halka dolgusundan bir tık koyu (#D98D72 / #DD9D85).
    let tint: Color
    /// Eğrinin altındaki düz dolgu. Görselde gradyan YOK: tek ton (#FDF2EE).
    let areaFill: Color
    /// Gelecek tahmin eğrisi (x: pencere konumu, y: kullanım%). Boşsa tahmin
    /// çizilmiyor.
    let forecast: [SparkPoint]
    /// Tahmin pencere kapanmadan %100'e varıyor mu.
    let willOverrun: Bool

    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(
                    x: size.width * min(max(x, 0), 1),
                    y: size.height * (1 - min(max(y, 0), 100) / 100)
                )
            }

            // Ölçek etiketlerinin karşılığı olan çok soluk yatay çizgiler.
            // Etiket olup çizgi olmayınca %50 nereye denk geliyor okunmaz.
            for step in YAxisScale.steps {
                // Uçtaki çizgiler tuvalin İÇİNDE kalmalı: 0 çizgisi tam
                // `size.height`e düşüyor, yarım piksel kaydırılınca dışarı
                // çıkıp hiç çizilmez — "0" etiketinin karşısında çizgi
                // kalmaz. Grafik kısaldıkça eksik taban daha da göze batıyor.
                let y = min(max(point(0, Double(step)).y.rounded() + 0.5, 0.5),
                            size.height - 0.5)
                // Görselde ölçek çizgileri NOKTALI ve çok soluk.
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    // Opaklık 0,28: `tertiaryText` kontrast için koyu tutulduğundan
                    // ızgara çizgisinin EKRANDAKİ değeri bu opaklıkla soluk kalıyor.
                    with: .color(Palette.tertiaryText.opacity(0.28)),
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
            // aşım öngörüldüğünde çıkıyor; her tahmin kırmızı olsaydı "5 saatte
            // %100'e gelmeyeceksin" diyen bir grafik bile alarm rengiyle çizilirdi.
            guard history.last != nil else { return }
            // Tahmin YALNIZCA gerçek bir aşım öngörüldüğünde çiziliyor.
            //
            // Sıfırlanmaya kadar %100'e varmıyorsan gösterilecek bir uyarı yok;
            // eğri çizmek "şuraya kadar gideceksin" diyen gereksiz bir iddia
            // oluyor. Kart o durumda yalnızca ölçülmüş eğriyi gösteriyor.
            guard willOverrun, forecast.count >= 2 else { return }

            // Tahmin eğrisi, %100'ü kestiği noktaya kadar çiziliyor. Kesikli
            // olması "ölçüm değil tahmin" diyor. Haftalık pencerede de tahmin
            // düz bir çizgi.
            // İlk nokta zaten tavandaysa çizilecek bir gelecek yok. Bu dal
            // olmadan aşağıdaki döngü i = 0 için `forecast[-1]` okuyup
            // çöker: kullanım %100'e vardığında eğrinin ilk noktası tam
            // 100 oluyor ve çökme tam da kullanıcının limite bakmak için
            // popover'ı açtığı anda gerçekleşir.
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
        // oluyor; ani takas iki ayrı grafik varmış gibi görünür.
        .motion(value: projected)
    }
}

/// Grafik altındaki zaman ekseni etiketleri.
///
/// İki eksen de aynı fontta (`Typo.axis`): farklı puntoda eksenler grafiği
/// düzensiz gösterir. Görselde x ekseni cap 17 px → 7,1 pt, y ekseni 16 px →
/// 6,6 pt; aradaki fark ölçüm gürültüsü sınırında, ikisi tek değerde.
struct AxisLabels: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(Typo.axis)
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
/// birbirine yaklaştırır ve dört soluk çizgi eğriyle yarışır; yarı
/// nokta zaten okumanın gerektirdiği tek ara referans.
struct YAxisScale: View {
    static let steps = [100, 50, 0]

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, value in
                Text("\(value)")
                if index < Self.steps.count - 1 { Spacer(minLength: 0) }
            }
        }
        .font(Typo.axis)
        .monospacedDigit()
        .foregroundStyle(Palette.secondaryText)
        .lineLimit(1)
        // YALNIZCA yatayda: dikeyde de sabitlemek aradaki iki `Spacer`ı
        // `minLength`e (0) çökertiyor, üç etiket tek blok hâlinde dikey ortaya
        // toplanıyor ve grafiğin 0/50/100 çizgileriyle hizası kayıyor.
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: PopoverLayout.yAxisWidth, height: PopoverLayout.chartHeight, alignment: .trailing)
        .accessibilityHidden(true)
    }
}
