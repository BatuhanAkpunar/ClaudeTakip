import Foundation

/// Sunucu isteklerinin yeniden deneme durumu: kısa sessiz denemeler ve
/// üstel geri çekilme.
///
/// Geçici ağ hatasından sonra kısa aralıklı sessiz deneme yapılır.
/// 4 saniye × 5 deneme ≈ 20 saniyelik bir pencere: kopan bir bağlantının
/// geri gelmesi için yeterli, sunucuyu döverek yormak için değil. Bu
/// pencere de sonuç vermezse normal geri çekilme merdivenine düşülüyor
/// (1 → 2 → 5 → 15 → 30 dakika), yine sessizce.
public struct ServerRetryPolicy: Sendable, Equatable {
    /// Üstel geri çekilme: 1 → 2 → 5 → 15 → 30 dakika tavanı.
    ///
    /// Tavan yarım saat: oturum düştüğünde kullanıcı yeniden giriş yapana kadar
    /// beklemek zaten gerekiyor, ama uygulama tamamen sessizleşmemeli ki ağ
    /// geri geldiğinde kendi kendine toparlasın.
    public static let backoffLadder: [TimeInterval] = [60, 120, 300, 900, 1800]
    public static let quickRetryLimit = 5
    public static let quickRetryDelay: Duration = .seconds(4)

    /// Arka arkaya başarısız sunucu denemesi sayısı; üstel geri çekilmeyi besler.
    public private(set) var failureStreak = 0
    /// Bu andan önce yeni bir otomatik deneme yapılmıyor.
    ///
    /// Oturum düştüğünde çerez bilinçli olarak silinmiyor, ama 60 saniyelik
    /// tetik çalışmaya devam ettiği için bu sınır olmadan uygulama ölü bir
    /// çerezle günde ~1440 istek atar. Ne kullanıcıya faydası var ne de
    /// sunucuya karşı nazik.
    public private(set) var nextAttempt: Date?
    /// Geçici ağ hatasından sonra yapılan kısa aralıklı sessiz denemeler.
    public private(set) var quickRetryCount = 0

    public init() {}

    /// Otomatik bir deneme şu an yapılabilir mi.
    public func allowsAutomaticAttempt(at now: Date) -> Bool {
        guard let nextAttempt else { return true }
        return !(now < nextAttempt)
    }

    /// Geri çekilmeyi sıfırlar (başarı, kullanıcı isteği, uyanma).
    public mutating func clearBackoff() {
        failureStreak = 0
        nextAttempt = nil
    }

    public mutating func resetQuickRetries() {
        quickRetryCount = 0
    }

    /// Merdivende bir basamak ilerler, tavanda kalır.
    public mutating func backOff(now: Date) {
        failureStreak = min(failureStreak + 1, 5)
        nextAttempt = now.addingTimeInterval(Self.backoffLadder[failureStreak - 1])
    }

    public enum TransientOutcome: Sendable, Equatable {
        case retrySoon
        case backedOff
    }

    /// Geçici hata: sınır dolmadıysa kısa deneme, dolduysa geri çekilme.
    public mutating func recordTransientFailure(now: Date) -> TransientOutcome {
        guard quickRetryCount < Self.quickRetryLimit else {
            quickRetryCount = 0
            backOff(now: now)
            return .backedOff
        }
        quickRetryCount += 1
        return .retrySoon
    }

    /// Kısa deneme `userInitiated` DEĞİL: sayaçları sıfırlamadan, yalnızca
    /// bekleme sınırını kaldırıp isteği tekrar kuruyor.
    public mutating func bypassBackoffOnce() {
        nextAttempt = nil
    }
}
