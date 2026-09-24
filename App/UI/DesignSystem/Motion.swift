import SwiftUI

// MARK: - Hareket

/// Uygulamanın hareket dili.
///
/// Menü çubuğu popover'ı bir saniyeliğine açılıp kapanıyor: burada animasyon
/// süsleme değil, DEĞİŞİMİ GÖRÜNÜR KILMA aracı. Ölçüt tek: hareket bir bilgi
/// taşıyor mu? Bir sayının artışını izlemek "ne kadar arttı" sorusunu
/// cevaplıyor, dolayısıyla değer geçişleri animasyonlu. Bir kartın içeri
/// zıplaması hiçbir şey söylemiyor, dolayısıyla öyle bir hareket yok.
///
/// Süreler kısa: 0,3 saniyenin üstü menü çubuğu bağlamında beklemeye dönüşüyor.
enum Motion {
    /// Ölçülen bir değer değişti (yüzde, oran, grafik).
    static let value = Animation.easeOut(duration: 0.28)
    /// Görünüm değişti (sekme, kart, şerit).
    static let view = Animation.easeInOut(duration: 0.16)
    /// Yerleşime giren/çıkan öğeler.
    static let layout = Animation.easeInOut(duration: 0.2)
}

/// "Hareketi Azalt" açıkken animasyonu tümüyle kaldıran değer izleyici.
///
/// Sistem ayarı vestibüler rahatsızlığı olan kullanıcılar için var ve bir
/// erişilebilirlik gereği: animasyon olan her yerde bu denetim zorunlu.
private struct MotionValue<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Verilen değer değiştiğinde animasyon uygular, "Hareketi Azalt"a saygılı.
    func motion<V: Equatable>(_ animation: Animation = Motion.value, value: V) -> some View {
        modifier(MotionValue(animation: animation, value: value))
    }
}
