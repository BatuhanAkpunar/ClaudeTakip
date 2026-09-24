import Testing
import Foundation
@testable import LimitCore

// Format, Calendar.current ve varsayılan saat dilimiyle çalışıyor; tarihler de
// aynı saat diliminde kuruluyor, dolayısıyla sonuç çalıştırılan makinenin saat
// diliminden bağımsız. Dil her testte `L.$languageOverride` ile sabitleniyor.
@Suite("Biçim")
struct FormatTests {
    private static func date(_ d: Int, _ m: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }

    /// Pace'te 1 bir EŞİK: üstü sıfırlanmadan dolmak demek. Tek ondalıkla
    /// 0,96 ve 1,04 ikisi de "1,0×" görünüyordu; yuvarlama eşiği geçmemeli.
    @Test("Pace biçimi eşiği geçmiyor")
    func paceFormat() {
        let cases: [(Double, String)] = [
            (0.6, "0,6×"), (1.3, "1,3×"), (1.0, "1,0×"), (0.949, "0,9×"), (1.051, "1,1×"),
            (0.96, "0,96×"), (1.04, "1,04×"), (0.996, "0,99×"), (1.004, "1,01×"),
        ]
        L.$languageOverride.withValue(.turkish) {
            for (value, expected) in cases {
                #expect(Format.multiplier(value) == expected, "\(value)")
            }
        }
    }

    /// Tasarımdaki "19 Eylülde sıfırlanır" cümlesi Türkçede ekin tarihe göre
    /// değişmesini gerektiriyor. On iki ay adı elle yazılmış bir tablo değil
    /// kuraldan türetiliyor, dolayısıyla sınanması gerekiyor.
    @Test("Sıfırlanma cümlesi: 12 ay eki")
    func monthLocatives() {
        let months = [
            (1, "Ocakta"), (2, "Şubatta"), (3, "Martta"), (4, "Nisanda"),
            (5, "Mayısta"), (6, "Haziranda"), (7, "Temmuzda"), (8, "Ağustosta"),
            (9, "Eylülde"), (10, "Ekimde"), (11, "Kasımda"), (12, "Aralıkta"),
        ]
        L.$languageOverride.withValue(.turkish) {
            for (m, expected) in months {
                let got = Format.resetSentence(Self.date(1, m), includeTime: false)
                #expect(got.hasPrefix("1 \(expected) sıfırlanır"), "\(m): \(got)")
            }
        }
    }

    @Test("Sıfırlanma cümlesi: saat eki")
    func timeLocatives() {
        let times: [(Int, Int, String)] = [
            (10, 0, "10:00da"), (5, 0, "05:00te"), (19, 0, "19:00da"),
            (13, 0, "13:00te"), (9, 30, "09:30da"), (14, 40, "14:40ta"),
            (8, 5, "08:05te"), (11, 11, "11:11de"),
        ]
        L.$languageOverride.withValue(.turkish) {
            for (h, m, expected) in times {
                #expect(Format.resetSentenceTimeOnly(Self.date(19, 9, h, m)) == "\(expected) sıfırlanır")
            }
        }
    }

    // Sunucu saniyeli veriyor; etiket dakikaya YUVARLANMALI, kırpılmamalı.
    @Test("Sıfırlanma saati dakikaya yuvarlanıyor")
    func rounding() {
        let roundings: [(Date, String)] = [
            (Self.date(19, 9, 9, 59).addingTimeInterval(59.8), "10:00da sıfırlanır"),
            (Self.date(19, 9, 9, 59).addingTimeInterval(29), "09:59da sıfırlanır"),
            (Self.date(19, 9, 9, 59).addingTimeInterval(31), "10:00da sıfırlanır"),
        ]
        L.$languageOverride.withValue(.turkish) {
            for (d, expected) in roundings {
                #expect(Format.resetSentenceTimeOnly(d) == expected)
            }
        }
    }

    @Test("Gece yarısına yuvarlanan an ertesi günü yazıyor")
    func midnight() {
        L.$languageOverride.withValue(.turkish) {
            let midnight = Format.resetSentence(Self.date(18, 9, 23, 59).addingTimeInterval(45), includeTime: true)
            #expect(midnight.hasPrefix("19 Eylül 00:00"), "\(midnight)")
        }
    }

    @Test("İngilizce biçimler")
    func english() {
        L.$languageOverride.withValue(.english) {
            #expect(Format.multiplier(1.0) == "1.0×")
            #expect(Format.multiplier(1.04) == "1.04×")
            #expect(Format.resetSentence(Self.date(1, 10), includeTime: false) == "Resets on October 1")
            #expect(Format.resetSentenceTimeOnly(Self.date(19, 9, 10, 0)) == "Resets at 10:00")
        }
    }

    // Sabit bir an: 19 Eylül 2026 Cumartesi 10:00 (yerel saat).
    @Test("Saat etiketi iki dilde")
    func hourLabelPattern() {
        let d = Self.date(19, 9, 10, 0)
        L.$languageOverride.withValue(.turkish) { #expect(Format.hourLabel(d) == "10:00") }
        L.$languageOverride.withValue(.english) { #expect(Format.hourLabel(d) == "10:00") }
    }

    @Test("Tarih-saat damgası iki dilde")
    func stampPattern() {
        let d = Self.date(19, 9, 10, 0)
        L.$languageOverride.withValue(.turkish) { #expect(Format.stamp(d) == "19 Eyl 10:00") }
        L.$languageOverride.withValue(.english) { #expect(Format.stamp(d) == "Sep 19 10:00") }
        // Saniye kırpılmıyor, dakikaya yuvarlanıyor.
        let justBefore = d.addingTimeInterval(-0.2)
        L.$languageOverride.withValue(.turkish) { #expect(Format.stamp(justBefore) == "19 Eyl 10:00") }
    }

    @Test("Kısa tarih iki dilde")
    func shortDatePattern() {
        let d = Self.date(19, 9, 10, 0)
        L.$languageOverride.withValue(.turkish) { #expect(Format.shortDate(d) == "19 Eyl") }
        L.$languageOverride.withValue(.english) { #expect(Format.shortDate(d) == "Sep 19") }
    }

    @Test("Kısa gün adı iki dilde")
    func weekdayPattern() {
        let d = Self.date(19, 9, 10, 0)
        L.$languageOverride.withValue(.turkish) { #expect(Format.weekdayShort(d) == "Cmt") }
        L.$languageOverride.withValue(.english) { #expect(Format.weekdayShort(d) == "Sat") }
    }

    @Test("Yüzde işaretinin yeri dile bağlı")
    func percentLabel() {
        L.$languageOverride.withValue(.turkish) { #expect(Format.percent(82.6) == "%83") }
        L.$languageOverride.withValue(.english) { #expect(Format.percent(82.6) == "83%") }
    }
}
