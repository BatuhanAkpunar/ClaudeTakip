import Foundation
import LimitCore

/// Bulut yedeği: cihaz kimliği, anonimden hesaba devir ve yükleme işaretleri.
///
/// Gözlenen durum tutmuyor; arayüz buradan hiçbir şey okumuyor.
@MainActor
final class CloudBackup {
    private let history: HistoryStore?
    private let cloud = CloudSync()
    private let store = CloudStore()
    private var syncing = false

    /// Yüklemeye eklenen plan etiketi. Yükleme anında okunur.
    var planLabel: @MainActor () -> String? = { nil }
    /// Buluttan geri yükleme arşive satır eklediğinde çağrılır.
    var onRestored: @MainActor () -> Void = {}

    init(history: HistoryStore?) {
        self.history = history
    }

    private var cloudEnabled: Bool {
        // Ayarlardaki "Bulut yedeği" anahtarı yazıyor; hiç dokunulmadıysa açık.
        UserDefaults.standard.object(forKey: SettingsKey.cloudSyncEnabled) as? Bool ?? true
    }

    /// Bulut kimliğini garantiler, yoksa kaydeder.
    private func ensureIdentity() async throws -> CloudIdentity {
        if let existing = store.identity { return existing }
        let fresh = try await cloud.register()
        store.save(identity: fresh)
        return fresh
    }

    /// Hesap kimliği öğrenildiğinde bir kez çalışan geçiş.
    ///
    /// Bulut verisinin kanonik sahibi cihaz değil hesap. Bu fonksiyon dört
    /// senaryoyu birden çözüyor:
    ///
    /// - Anonim → giriş: bu cihazın buluttaki anonim satırları `/v1/claim`
    ///   ile hesaba devrediliyor, hiç yüklenmemiş yerel satırlar da (senkron
    ///   kapalıyken birikenler) işaret sıfırlandığı için hesabın altına
    ///   gönderiliyor. Giriş öncesi geçmiş kaybolmuyor.
    /// - Aynı cihazda giriş: anahtar değişmediği için hiçbir şey yapılmıyor.
    /// - Yeni cihaz: hesabın buluttaki geçmişi indirilip yerel arşive
    ///   karışıyor.
    /// - Yeni cihazda önce anonim kullanım: ikisi birden, önce devir sonra
    ///   indirme.
    ///
    /// Mükerrer kayıt oluşmuyor: yerel arşivin birincil anahtarı zaman
    /// damgası, buluttaki tablonun anahtarı ise (cihaz, zaman).
    func adopt(organizationID: String) {
        let key = AccountKey.derive(organizationID: organizationID)
        guard AccountKey.isValid(key), store.accountKey != key else { return }

        store.save(accountKey: key)
        // Yükleme işareti sıfırlanıyor ki daha önce gönderilmemiş satırlar da
        // hesaba gitsin. Yükleme idempotent olduğu için tekrar göndermek
        // güvenli: aynı (cihaz, zaman) ikinci kez satır açmıyor.
        store.resetWatermark()
        guard cloudEnabled else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await ensureIdentity()
                try await cloud.claim(identity: identity, accountKey: key)
            } catch {
                // Devir başarısızsa veri kaybolmuyor: kaynak yerel arşiv,
                // bir sonraki turda yeniden denenir.
            }
            self.sync()
            self.restore()
        }
    }

    /// Hesap anahtarı bırakılıyor: bundan sonraki kayıtlar yine anonim ve
    /// cihaza ait. Buluttaki hesap geçmişi silinmiyor, yeniden giriş
    /// yapıldığında olduğu gibi geri geliyor.
    func releaseAccount() {
        store.save(accountKey: nil)
    }

    /// Buluttaki veriyi siler ve yedeklemeyi KAPATIR.
    ///
    /// Kapatmak şart: silme cihaz kaydını da götürüyor, kimlik atılınca
    /// yükleme işareti sıfırlanıyor ve açık kalan senkron bir sonraki turda
    /// tüm yerel arşivi yeniden yüklerdi. Ayar silmeden ÖNCE kapatılıyor ki
    /// araya bir yükleme girmesin. Hiç kayıt yoksa silinecek bir şey de yok.
    func eraseCloud() async -> Bool {
        UserDefaults.standard.set(false, forKey: SettingsKey.cloudSyncEnabled)
        guard let identity = store.identity else { return true }
        do {
            try await cloud.deleteEverything(identity: identity, accountKey: store.accountKey)
        } catch CloudSync.SyncError.notRegistered {
            // Sunucu cihazı zaten tanımıyor: silinecek bir şey kalmamış.
        } catch {
            return false
        }
        store.clearIdentity()
        return true
    }

    /// Yerel arşivi buluta yedekler.
    ///
    /// Tek yönlü: yerel kaynak, bulut kopya. Yalnızca son yüklemeden sonraki
    /// örnekler gönderiliyor, dolayısıyla her çalıştırma birkaç satır.
    /// Girişliyken satırlar hesap anahtarıyla etiketleniyor.
    func sync() {
        guard cloudEnabled, !syncing, let history else { return }
        syncing = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await ensureIdentity()
                let accountKey = store.accountKey

                // İlk yüklemede geçmişin tamamı gidiyor, sonrasında yalnızca yenisi.
                let watermark = store.uploadedThrough ?? .distantPast
                let pending = ((try? history.samples(since: watermark)) ?? [])
                    .filter { $0.date > watermark }

                if !pending.isEmpty {
                    try await cloud.upload(pending, plan: planLabel(),
                                           identity: identity, accountKey: accountKey)
                    if let newest = pending.last?.date {
                        store.save(uploadedThrough: newest)
                    }
                }
                // `/v1/summary` artık çağrılmıyor: sonucunu hiçbir yer
                // göstermiyordu, 15 dakikada bir boşuna istekti.
                self.syncing = false
            } catch CloudSync.SyncError.notRegistered {
                // Cihaz kaydı sunucuda yok. Kimliği atıp bir sonraki turda
                // yeniden kaydolunuyor; veri yerelde durduğu için kayıp yok.
                // Hesap anahtarı korunuyor: yeniden kayıttan sonraki
                // yüklemeler de hesabın altına gitsin.
                store.clearIdentity()
                self.syncing = false
            } catch {
                self.syncing = false
            }
        }
    }

    /// Buluttaki geçmişi yerel arşive geri yükler. Yeni makine senaryosu.
    ///
    /// Girişliyse hesabın tüm cihazlarındaki geçmiş geliyor. İçe aktarma
    /// mükerrer üretmiyor: arşivin birincil anahtarı zaman damgası, aynı an
    /// ikinci kez yazılmıyor.
    private func restore() {
        guard let identity = store.identity, let history else { return }
        let accountKey = store.accountKey
        Task { [weak self] in
            guard let self else { return }
            let samples = (try? await cloud.download(
                since: .distantPast, identity: identity, accountKey: accountKey)) ?? []
            guard !samples.isEmpty else { return }
            // İçe aktarma ana aktörün DIŞINDA: tüm hesap geçmişi binlerce
            // satır olabiliyor ve bu Task ana aktörde çalışıyor.
            await Task.detached(priority: .utility) {
                _ = try? history.importSamples(samples)
            }.value
            self.onRestored()
        }
    }
}
