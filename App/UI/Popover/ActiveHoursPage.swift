import SwiftUI
import LimitCore

/// "En Aktif Saatler"in ayrıntı sayfası: popover'ın ikinci sayfası.
///
/// İki katman, fazlası yok: ana sayfadaki 24 hücreli şerit özet, burası
/// ayrıntı. Burada iki şey var:
///
/// 1. Hafta günü × saat ısı haritası. Düz şerit hafta içi ile hafta sonunu
///    aynı satırda ortalıyor; çalışma düzeni çoğu zaman tam orada ayrışıyor.
/// 2. Saatlik tablo: kesin sayılar. Isı haritası deseni gösteriyor, tablo
///    "14:00'te ne kadar" sorusunu okutuyor; ekran okuyucu ve renk ayırt
///    edemeyen kullanıcı için de aynı bilginin ikinci kanalı.
///
/// Ayarlar sayfasıyla aynı kalıp: aynı genişlik, yerinde çapraz geçiş.
struct ActiveHoursPage: View {
    let profile: UsageProfile
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: PopoverLayout.cardSpacing) {
            header

            MetricCard {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: L.t("Hafta Günü × Saat", "Weekday × Hour"))
                    WeekdayHourGrid(profile: profile)
                }
            }

            MetricCard {
                VStack(alignment: .leading, spacing: 6) {
                    CardHeader(title: L.t("Saat Saat", "Hour by Hour"))
                    HourTable(profile: profile)
                }
            }
        }
        .padding(PopoverLayout.outerPadding)
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        ZStack {
            Text(L.t("En Aktif Saatler", "Most Active Hours"))
                .font(Typo.title)
                .foregroundStyle(Palette.primaryText)

            HStack {
                HeaderButton(systemName: "chevron.left", help: L.t("Geri", "Back"), action: onBack)
                Spacer()
            }
        }
        .padding(.horizontal, PopoverLayout.headerInset)
        .padding(.top, 2)
    }
}

// MARK: - Hafta günü × saat

/// 7 satır × 24 sütun ısı haritası. Ana şeritle aynı renk rampası ve aynı
/// hücre ızgarası; satır başında gün kısaltması.
private struct WeekdayHourGrid: View {
    let profile: UsageProfile

    private static let rowHeight: CGFloat = 13
    private static let rowGap: CGFloat = 3
    private static let labelWidth: CGFloat = 26
    private static var axisBand: CGFloat { SFMetrics.band(Typo.axisSize) }
    private static let axisGap: CGFloat = 4

    static var height: CGFloat {
        7 * rowHeight + 6 * rowGap + axisGap + axisBand
    }

    static var dayNames: [String] { [
        L.t("Pzt", "Mon"), L.t("Sal", "Tue"), L.t("Çar", "Wed"), L.t("Per", "Thu"),
        L.t("Cum", "Fri"), L.t("Cmt", "Sat"), L.t("Paz", "Sun"),
    ] }

    private var peak: Double {
        max(0.001, profile.weekdayHourly.flatMap { $0 }.max() ?? 0)
    }

    var body: some View {
        Canvas { ctx, size in
            let gridX = Self.labelWidth
            let step = (size.width - gridX) / 24
            let cellW = step - step * PopoverLayout.heatGapRatio
            let radius = min(PopoverLayout.heatCellRadius - 1, cellW * 0.31)

            for weekday in 0..<7 {
                let y = CGFloat(weekday) * (Self.rowHeight + Self.rowGap)
                let label = ctx.resolve(
                    Text(Self.dayNames[weekday]).font(Typo.axis)
                        .foregroundStyle(Palette.secondaryText)
                )
                ctx.draw(label, at: CGPoint(x: 0, y: y + Self.rowHeight / 2), anchor: .leading)

                for hour in 0..<24 {
                    let rect = CGRect(x: gridX + CGFloat(hour) * step, y: y,
                                      width: cellW, height: Self.rowHeight)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                        with: .color(Palette.heat(profile.weekdayHourly[weekday][hour] / peak))
                    )
                }
            }

            let axisY = 7 * Self.rowHeight + 6 * Self.rowGap + Self.axisGap
            for hour in [0, 6, 12, 18, 23] {
                let text = ctx.resolve(
                    Text(String(format: "%02d", hour)).font(Typo.axis).monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                )
                let half = text.measure(in: size).width / 2
                let center = gridX + CGFloat(hour) * step + cellW / 2
                ctx.draw(text, at: CGPoint(x: min(max(center, half), size.width - half), y: axisY),
                         anchor: .top)
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(L.t("Hafta günü ve saate göre aktiflik", "Activity by weekday and hour"))
        .accessibilityValue(summary)
    }

    /// Ekran okuyucu için: her gün en aktif saati.
    private var summary: String {
        (0..<7).compactMap { weekday -> String? in
            let row = profile.weekdayHourly[weekday]
            guard let best = row.max(), best > 0, let hour = row.firstIndex(of: best) else { return nil }
            return "\(Self.dayNames[weekday]) \(String(format: "%02d:00", hour))"
        }.joined(separator: ", ")
    }
}

// MARK: - Saatlik tablo

/// 24 satırlık kesin değer tablosu. Kaydırılabilir: popover ekrana sığsın.
private struct HourTable: View {
    let profile: UsageProfile

    private static let visibleHeight: CGFloat = 210

    var body: some View {
        let peakHour = profile.peakHour
        VStack(spacing: 0) {
            row(hour: L.t("Saat", "Hour"), active: L.t("Aktiflik", "Activity"),
                usage: L.t("Tüketim", "Usage"), days: L.t("Gözlem", "Observed"),
                font: Typo.badge, ink: Palette.secondaryText, highlighted: false)
                .padding(.bottom, 3)

            Rectangle().fill(Palette.separator).frame(height: 0.5)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        let observed = profile.hourSampleDays[hour]
                        row(
                            hour: String(format: "%02d:00", hour),
                            active: observed > 0 ? Self.percent(profile.hourly[hour]) : "—",
                            usage: profile.intensity[hour] > 0
                                ? String(format: "%.1f", profile.intensity[hour]) : "—",
                            days: observed > 0 ? L.t("\(observed) gün", "\(observed) d") : "—",
                            font: Typo.footnote.monospacedDigit(),
                            ink: Palette.primaryText,
                            highlighted: hour == peakHour
                        )
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 2)
            }
            .frame(height: Self.visibleHeight)
        }
    }

    /// Türkçede yüzde işareti başta ("%80"), İngilizcede sonda ("80%").
    private static func percent(_ share: Double) -> String {
        let value = Int((share * 100).rounded())
        return L.t("%\(value)", "\(value)%")
    }

    private func row(hour: String, active: String, usage: String, days: String,
                     font: Font, ink: Color, highlighted: Bool) -> some View {
        HStack(spacing: 0) {
            Text(hour).frame(width: 56, alignment: .leading)
            Text(active).frame(maxWidth: .infinity, alignment: .trailing)
            Text(usage).frame(maxWidth: .infinity, alignment: .trailing)
            Text(days).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(highlighted ? font.weight(.semibold) : font)
        .foregroundStyle(ink)
        .padding(.vertical, 2.5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(highlighted ? Palette.heat(0.30) : Color.clear)
        )
    }
}
