import SwiftUI

/// Punto ölçeği.
///
/// Gösterim puntoları ölçülü (başlık 15, halka ve kahraman sayı 20); ölçeğin
/// ALT UCU ise 9-11,5 pt: bu yazılar zaten okunabilirliğin tabanında. Küçüğü
/// de küçültmek ölçeği düzleştirir, yani hiyerarşi kaybolur. Aradaki farkı
/// AĞIRLIK ve RENK taşıyor:
/// kart başlıkları kalın 13 pt yerine 10 pt versal bölüm etiketi
/// (`sectionLabel`), böylece kahraman sayıyla ağırlık yarışına girmiyorlar.
enum Typo {
    // Punto SAYILARI: `Font` değerinden boyut geri okunamadığı için Canvas
    // hesapları puntoyu buradan alır; elle yazılan ikinci bir sayı punto
    // değişince sessizce yanlış olur. Tek kaynak burası.
    static let axisSize: CGFloat = 9
    static let heatPeakSize: CGFloat = 9

    static let title        = Font.system(size: 15, weight: .bold)
    /// Kart başlığı: küçük, versal, harf aralığı açık BÖLÜM ETİKETİ.
    static let sectionLabel = Font.system(size: 10, weight: .semibold)
    /// Versal yazı harf aralığı olmadan sıkışık okunuyor.
    static let sectionLabelTracking: CGFloat = 0.6
    /// Bölüm etiketi olmayan kart başlıkları (giriş daveti gibi cümleler).
    static let cardTitle    = Font.system(size: 12, weight: .bold)
    /// Halkanın içindeki yüzde. `donutSize` ile birlikte hareket eder.
    static let donutValue   = Font.system(size: 20, weight: .bold).monospacedDigit()
    static let donutCaption = Font.system(size: 10)
    static let heroValue    = Font.system(size: 20, weight: .bold).monospacedDigit()
    static let heroLabel    = Font.system(size: 10)
    static let chartTitle   = Font.system(size: 11, weight: .semibold)
    /// Hız çarpanı. `footnote` ile aynı puntoda ama MEDIUM: "1,25×" bir DEĞER,
    /// yanındaki "kullanım hızı" bir etiket. İkisi birebir aynı fontta olsa
    /// hangisinin değer olduğunu yalnızca renk söylerdi.
    static let rateValue    = Font.system(size: 10, weight: .medium).monospacedDigit()
    /// Durum rozetinin içi.
    static let badge        = Font.system(size: 9.5, weight: .semibold)
    /// Grafik eksenleri. Ölçeğin en küçük değeri.
    static let axis         = Font.system(size: axisSize)
    /// Kart altı meta satırı.
    static let footnote     = Font.system(size: 10)
    /// Başlık şeridindeki yuvarlak denetimlerin simgesi (22 pt yüzeye oranlı).
    static let headerIcon   = Font.system(size: 10.5, weight: .medium)
    static let body         = Font.system(size: 11.5)
    static let tab          = Font.system(size: 11, weight: .semibold)
    static let heatPeak     = Font.system(size: heatPeakSize, weight: .semibold).monospacedDigit()
}

/// San Francisco'nun ölçülen satır kutusu oranı.
///
/// Canvas içindeki şeritler puntodan TÜRETİLİYOR. Elle yazılan sabitler punto
/// değişince sessizce yanlış olur (ör. `HourStream`in saat ekseni için 8,3 pt
/// yetmez, gereken 10,7; daha azında rakamların altı kırpılır).
enum SFMetrics {
    /// Tam satır kutusu. `GraphicsContext.draw(_:at:anchor: .top)` yazının
    /// LAYOUT kutusunu hizalıyor — yani `measure(in:)`in döndürdüğü tam kutuyu,
    /// büyük harf yüksekliğini değil. Ayrılan şerit bu kadar olmalı.
    private static let lineBox: CGFloat = 1.1796

    static func band(_ size: CGFloat) -> CGFloat { (size * lineBox).rounded(.up) }
}
