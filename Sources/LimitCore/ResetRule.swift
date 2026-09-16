import Foundation

/// İki ardışık örnek arasında pencerenin sıfırlanıp sıfırlanmadığı.
///
/// Kural tek bir yerde: aynı mantık hem `WindowDeriver` (mevcut pencereyi
/// bulmak) hem `Projector` (geçmiş haftaları ayırmak) tarafından kullanılıyor.
/// Kopyalandığı sürece ikisi sessizce birbirinden ayrılabiliyordu.
public enum ResetRule {
    /// Bir puanlık gerilemeyi sıfırlanma saymamak için gereken en küçük taban.
    ///
    /// Seride üç kaynak karışıyor (Claude Desktop dosyası, sunucu okuması,
    /// buluttan gelen ikinci cihaz); yuvarlamaları ve gecikmeleri farklı.
    /// `current <= 2` kuralı tek başına önceki değere bakmıyordu, yani 1 → 0
    /// gibi bir gürültü de sıfırlanma sayılıyordu: kullanıcının gerçek
    /// arşivinde tespit edilen sıfırlanmaların bir kısmı buydu ve her biri
    /// pencereyi ortasından kesip hız hesabını bozuyordu.
    static let minimumMeaningfulLevel = 10

    /// İki örnek arasında sıfırlanma oldu mu.
    ///
    /// - Parameters:
    ///   - previous: önceki örneğin yüzdesi
    ///   - current: sonraki örneğin yüzdesi
    ///   - gap: iki örnek arasındaki süre
    ///   - duration: pencere boyu
    public static func didReset(
        previous: Int, current: Int, gap: TimeInterval, duration: TimeInterval
    ) -> Bool {
        // Boşluk pencere boyundan uzunsa sıfırlanma KESİN olmuştur, değer
        // düşmese bile: uygulama kapalıyken pencere döndü ve yeni pencerede
        // benzer bir yüzdeye ulaşıldı. Eskiden yalnızca düşüşe bakıldığı için
        // bu durum tümüyle görünmezdi ve iki ayrı pencere tek pencere gibi
        // birleşip hem hızı hem tahmini bozuyordu.
        if gap > duration { return true }

        guard current < previous else { return false }
        let drop = previous - current
        // Anlamlı bir birikimin sıfıra yakın bir yere düşmesi ya da değerin
        // çoğunu kaybetmesi.
        return (current <= 2 && previous >= minimumMeaningfulLevel) || drop >= max(5, previous / 2)
    }
}
