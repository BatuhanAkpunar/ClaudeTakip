import Foundation

extension Projector {
    /// Geçmiş tüketim sadece GÜN İÇİ DAĞILIMI belirler. Bu haftanın tüketimi
    /// geçen bölümün desen ağırlığına bölünerek ölçeklenir; dolayısıyla geçmiş
    /// bir planın kota büyüklüğü bugünkü plana taşınmaz. Gece ve geçmiş limit
    /// beklemeleri düşük/sıfır ağırlıklı kalır. Gelecekteki oturum başlangıçları
    /// bilinmediği için yalnızca şu an kesin bilinen engel ayrıca uygulanır.
    func weeklyProjection(
        _ state: WindowState, now: Date, profile: UsageProfile?,
        blockedUntil: Date?, calendar: Calendar
    ) -> Projection? {
        guard let start = state.windowStart, let reset = state.resetAt else { return nil }
        let current = Double(state.utilization)
        let duration = reset.timeIntervalSince(start)
        let elapsedHours = now.timeIntervalSince(start) / 3600
        let historical = profile.flatMap { p -> UsageProfile? in
            guard p.observedDays >= 7, p.forecastActiveDays >= 3, p.forecastHourly.reduce(0, +) > 0 else { return nil }
            return p
        }

        func weight(at date: Date, using pattern: UsageProfile?) -> Double {
            guard let pattern else { return 1 }
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7
            return pattern.forecastWeekdayHourly[weekday][calendar.component(.hour, from: date)]
        }
        // Takvim saatinin gerçek sonu: yarım saatlik saat dilimleri ve DST
        // günlerinde epoch % 3600 yerel saat sınırı değildir.
        func hourEnd(_ date: Date) -> Date {
            calendar.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(3600)
        }
        var elapsedWeight = 0.0
        var cursor = start
        while cursor < now {
            let end = min(now, hourEnd(cursor))
            guard end > cursor else { return nil }
            elapsedWeight += weight(at: cursor, using: historical) * end.timeIntervalSince(cursor) / 3600
            cursor = end
        }
        // Bu haftanın geçen bölümünde tarihsel desen hiç çalışmıyorsa o
        // desene bölmek mümkün değil. En az bir günlük takvim ortalaması.
        let pattern = elapsedWeight > 0 ? historical : nil
        let scale = current / (pattern == nil ? elapsedHours : elapsedWeight)
        let resume = min(reset, max(now, blockedUntil ?? now))
        var projected = current
        var fillAt: Date?
        var points = [ProjectionPoint(position: now.timeIntervalSince(start) / duration, utilization: current)]
        cursor = now
        while cursor < reset {
            var end = min(reset, hourEnd(cursor))
            if cursor < resume { end = min(end, resume) }
            guard end > cursor else { return nil }
            let rate = cursor < resume ? 0 : scale * weight(at: cursor, using: pattern)
            let increase = rate * end.timeIntervalSince(cursor) / 3600
            if fillAt == nil, rate > 0, projected + increase >= 100 {
                fillAt = cursor.addingTimeInterval((100 - projected) / rate * 3600)
            }
            projected += increase
            points.append(ProjectionPoint(position: end.timeIntervalSince(start) / duration, utilization: projected))
            cursor = end
        }
        return Projection(
            ratePerHour: (projected - current) / (reset.timeIntervalSince(now) / 3600),
            multiplier: projected / 100, projectedUtilization: projected,
            fillAt: fillAt, willOverrun: fillAt != nil, forecast: points,
            usesActivityPattern: pattern != nil
        )
    }
}
