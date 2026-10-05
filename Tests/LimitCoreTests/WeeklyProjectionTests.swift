import Foundation
import Testing
@testable import LimitCore

@Suite("Haftalık davranış tahmini")
struct WeeklyProjectionTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    func state(_ used: Int, start: Date) -> WindowState {
        WindowState(kind: .sevenDay, utilization: used, windowStart: start,
                    resetAt: start.addingTimeInterval(7 * 86400), startUncertainty: 0,
                    isIdle: false, observedResets: [])
    }
    func profile(days: Int = 14) -> UsageProfile {
        UsageProfile(hourly: Array(repeating: 0, count: 24),
                     hourSampleDays: Array(repeating: days, count: 24), observedDays: days,
                     forecastHourly: (0..<24).map { (9..<17).contains($0) ? 1 : 0 })
    }

    @Test("Gece tüketim çizgisi düz kalır, dolma çalışma saatine düşer")
    func sleepIsRespected() throws {
        // İki günde 16 aktif saat / %60 → kalan %40 için 10 saat 40 dk çalışma gerekir.
        let start = date(1), now = date(2, 22)
        let p = try #require(Projector().project(state(60, start: start), now: now,
                                                profile: profile(), calendar: calendar))
        #expect(p.usesActivityPattern)
        let fill = try #require(p.fillAt)
        #expect(abs(fill.timeIntervalSince(date(4, 11).addingTimeInterval(2400))) < 0.01)
        let overnight = p.forecast.filter { start.addingTimeInterval($0.position * 7 * 86400) <= date(3, 9) }
        #expect(overnight.allSatisfy { $0.utilization == 60 })
        #expect(abs((p.multiplier ?? 0) - p.projectedUtilization / 100) < 1e-9)
    }

    @Test("Dolu 5 saatlik limitin sıfırlanmasına kadar tahmin artmaz")
    func currentLimitWait() throws {
        let start = date(1), now = date(3, 9), resume = date(3, 12)
        let p = try #require(Projector().project(state(80, start: start), now: now,
                                                profile: profile(), blockedUntil: resume, calendar: calendar))
        let fill = try #require(p.fillAt)
        #expect(fill == date(3, 16))
        #expect(p.forecast.filter { start.addingTimeInterval($0.position * 7 * 86400) <= resume }
            .allSatisfy { $0.utilization == 80 })
    }

    @Test("Az geçmişte bir günlük ortalama kullanılır, ilk gün pace yoktur")
    func sparseHistory() throws {
        let start = date(1)
        let early = try #require(Projector().project(state(20, start: start), now: date(1, 20),
                                                    profile: profile(), calendar: calendar))
        #expect(early.multiplier == nil)
        #expect(early.forecast.isEmpty)
        let p = try #require(Projector().project(state(20, start: start), now: date(3),
                                                profile: profile(days: 2), calendar: calendar))
        #expect(!p.usesActivityPattern)
        #expect(abs(p.projectedUtilization - 70) < 1e-8)
        #expect(p.fillAt == nil)
        #expect(!p.willOverrun)
    }

    @Test("Bilinen bekleme takvim ortalamasına da uygulanır")
    func waitWithoutProfile() throws {
        let start = date(1), now = date(3)
        let p = try #require(Projector().project(state(40, start: start), now: now,
                                                blockedUntil: now.addingTimeInterval(3 * 3600), calendar: calendar))
        let fill = try #require(p.fillAt)
        #expect(abs(fill.timeIntervalSince(start) / 3600 - 123) < 1e-8)
    }

    @Test("Desen ve ortalamada pace ile aşım her zaman aynı sonuca varır")
    func paceConsistency() throws {
        for days in 1...6 {
            for used in stride(from: 5, through: 95, by: 5) {
                let p = try #require(Projector().project(state(used, start: date(1)), now: date(1 + days, 19),
                                                        profile: profile(), calendar: calendar))
                #expect(((p.multiplier ?? 0) >= 1) == p.willOverrun)
                #expect(p.forecast.last?.utilization == p.projectedUtilization)
                #expect(p.forecast.last?.position == 1)
            }
        }
    }

    @Test("Sıfırlanmış pencereden geleceğe tahmin yapılmaz")
    func expiredWindow() {
        #expect(Projector().project(state(40, start: date(1)), now: date(8)) == nil)
    }

    @Test("DST geçişinde saat sınırları sonlu ve artandır")
    func daylightSaving() throws {
        var local = calendar
        local.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(local.date(from: DateComponents(year: 2026, month: 10, day: 30)))
        let p = try #require(Projector().project(state(50, start: start), now: start.addingTimeInterval(86400),
                                                profile: profile(), calendar: local))
        #expect(p.forecast.count < 180)
        for (a, b) in zip(p.forecast, p.forecast.dropFirst()) {
            #expect(b.position > a.position)
            #expect(b.utilization >= a.utilization)
        }
        #expect(p.forecast.last?.position == 1)
    }
}

extension WeeklyProjectionTests {
    @Test("Hafta sonu sıfır ağırlıklıysa cuma tüketimi pazartesiye taşınır")
    func weekendPattern() throws {
        let hours = (0..<24).map { (9..<17).contains($0) ? 1.0 : 0 }
        let grid = (0..<7).map { $0 < 5 ? hours : Array(repeating: 0.0, count: 24) }
        let p = UsageProfile(hourly: hours, hourSampleDays: Array(repeating: 21, count: 24),
                             observedDays: 21, forecastHourly: hours, forecastWeekdayHourly: grid)
        // Salı başlangıcı; cuma gecesi %90. 32 aktif saatte %90 → kalan %10
        // cumartesi/pazar değil pazartesi 3 saat 33 dakika sonra dolar.
        let projected = try #require(Projector().project(state(90, start: date(1)), now: date(4, 22),
                                                        profile: p, calendar: calendar))
        let fill = try #require(projected.fillAt)
        #expect(calendar.component(.day, from: fill) == 7)
        #expect(calendar.component(.hour, from: fill) == 12)
        #expect(projected.usesActivityPattern)
    }
}
