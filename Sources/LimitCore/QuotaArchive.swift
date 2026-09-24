import Foundation

/// Kota örneklerinin kalıcı arşivi üzerindeki tüm okuma ve yazmalar.
///
/// Yalnızca store tarafından, tek bir aktörden kullanılıyor; bu yüzden
/// Sendable değil. Arşiv açılamazsa (`history` nil) her işlem yerel veriyle
/// devam eder: kalıcı geçmiş bir iyileştirme, uygulamanın çalışma şartı değil.
public final class QuotaArchive {
    private let history: HistoryStore?

    public init(history: HistoryStore?) {
        self.history = history
    }

    /// Haftalık pencere en fazla 7 gün; 9 gün sıfırlanma zincirini de kapsıyor.
    public static let recentSpan: TimeInterval = 9 * 24 * 3600

    /// Kullanım profilinin baktığı geçmiş: son 60 gün.
    public static let profileSpan: TimeInterval = 60 * 24 * 3600

    /// Arşivin saklama süresi: 90 gün.
    ///
    /// Uygulamanın okuduğu en uzun dilim kullanım profilinin 60 günü
    /// (`profileSpan`); pencere hesapları yalnızca 9 güne bakıyor
    /// (`recentSpan`). 90 gün ikisini de rahatça kapsıyor ve senkron bir
    /// süre kapalı kalsa bile yüklenmemiş satırlara bir aylık pay bırakıyor.
    /// Dakikada bir satırla bu ~130 bin satır demek; budama olmadan arşiv
    /// sınırsız büyüyordu.
    public static let retention: TimeInterval = 90 * 24 * 3600

    /// Bu süreçte dosyadan arşive aktarılmış en yeni örneğin zamanı.
    private var importedThrough: Date?

    /// Budama günde bir yeter; her 30 saniyelik turda DELETE çalıştırmak boşuna.
    private static let pruneInterval: TimeInterval = 24 * 3600
    private var lastPrune: Date?

    /// Saklama süresinden eski satırları, günde en çok bir kez siler.
    func pruneIfDue(now: Date) {
        guard let history else { return }
        if let lastPrune, now.timeIntervalSince(lastPrune) < Self.pruneInterval { return }
        lastPrune = now
        _ = try? history.prune(before: now.addingTimeInterval(-Self.retention))
    }

    /// Arşivin satır sayısı ve en eski kaydı; istendiğinde arşivden okunur.
    public var stats: (count: Int, oldest: Date?) { history?.stats() ?? (0, nil) }

    /// Taze örnekleri arşive aktarır ve pencere hesapları için gereken aralığı
    /// arşivden döner.
    ///
    /// Arşiv erişilemezse taze örneklerle devam ediliyor: kalıcı geçmiş bir
    /// iyileştirme, uygulamanın çalışma şartı değil.
    public func merge(fresh: [QuotaSample]) -> [QuotaSample] {
        guard let history else { return fresh }
        // İlk birleştirmede dosyanın tamamı, sonrasında yalnızca bu süreçte
        // henüz aktarılmamış yeni satırlar. Dosya yalnızca sona ekleniyor;
        // her 30 saniyelik turda binlerce satırı ana iş parçacığında yeniden
        // INSERT OR IGNORE'dan geçirmek boşuna işti.
        let pending = importedThrough.map { cut in fresh.filter { $0.date > cut } } ?? fresh
        if (try? history.importSamples(pending)) != nil,
           let newest = pending.map(\.date).max() {
            importedThrough = max(importedThrough ?? newest, newest)
        }
        pruneIfDue(now: Date())

        let cutoff = Date().addingTimeInterval(-Self.recentSpan)
        guard let stored = try? history.samples(since: cutoff) else { return fresh }

        // Kıyas AYNI aralık üzerinden yapılmalı. Dokuz günlük arşiv dilimini
        // yirmi dokuz günlük dosyanın tamamıyla karşılaştırmak, arşivin hiçbir
        // zaman seçilmemesine ve özelliğin ölü kalmasına yol açıyordu.
        let freshInWindow = fresh.filter { $0.date >= cutoff }
        return stored.count >= freshInWindow.count ? stored : fresh
    }

    /// Pencere hesapları için arşivin son `recentSpan` dilimi.
    public func recent(now: Date) -> [QuotaSample] {
        (try? history?.samples(since: now.addingTimeInterval(-Self.recentSpan))) ?? []
    }

    /// Sunucudan gelen okumayı arşive yazar.
    ///
    /// Bu olmadan, Claude Desktop kurulu olmayan bir kullanıcıda arşiv hiç
    /// dolmuyor ve grafikler sonsuza kadar boş kalıyordu.
    public func record(_ usage: ServerUsage, at now: Date, org: String) {
        guard let history,
              let sample = QuotaSample(server: usage, date: now, org: org)
        else { return }

        _ = try? history.importSamples([sample])
        pruneIfDue(now: now)
    }

    /// Kullanım profili, arşivin son 60 gününden (`profileSpan`) kurulur.
    ///
    /// Saatlik desen ne kadar çok güne yayılırsa o kadar güvenilir.
    ///
    /// Sonuç önbellekleniyor: okuma 0,6 ms ama profil inşası 7,2 ms ve bu iş
    /// 30 saniyede bir ana iş parçacığında yapılır. Arşiv büyüdükçe
    /// doğrusal artıyor, oysa saatlik desen dakikalar içinde değişmiyor.
    private var profileCache: (profile: UsageProfile, at: Date)?
    private static let longRangeTTL: TimeInterval = 5 * 60

    public func profile(now: Date) -> UsageProfile {
        if let cache = profileCache, now.timeIntervalSince(cache.at) < Self.longRangeTTL {
            return cache.profile
        }
        let rows = history.map { (try? $0.samples(since: now.addingTimeInterval(-Self.profileSpan))) ?? [] } ?? []
        let built = UsageProfile.build(from: rows)
        profileCache = (built, now)
        return built
    }
}
