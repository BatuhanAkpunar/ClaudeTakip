import SwiftUI
import AppKit

/// Ölçüler mockup'tan geliyor, popover genişliğine uyarlanmış halde.
///
/// Mockup 1520 px genişliğinde iki sütunlu bir düzendi. Menü çubuğu popover'ında
/// iki sütun olamayacağı için kartlar tek sütuna alındı; kart dili, halkalar,
/// gradyan grafikler ve rozetler olduğu gibi korundu.
/// ÖLÇÜLER MOCKUP'TAN. Kaynak: kullanıcının 1278×1230 px tasarımı.
///
/// Popover'ın kendi dikdörtgeni görselde 1232 px; uygulamada 360 pt. Bütün
/// sayılar bu tek orandan geçirildi: **0,292208 pt/px**. Yorumlardaki "→"
/// işaretinin solundaki değer görselde ölçülen piksel, sağındaki uygulanan
/// punto. Göz kararı hiçbir değer yok; ölçülmeyen tek şey koyu tema
/// karşılıkları, çünkü görsel yalnızca açık temayı gösteriyor.
/// ÖLÇÜLER MOCKUP'TAN, tek bir orandan geçirilmiş.
///
/// Kaynak: kullanıcının 1278×1230 px tasarımı; popover dikdörtgeni orada
/// 1232 px. Pencere **480 pt** genişledi ve oran buradan çıkıyor:
/// **0,389610 pt/px**. Yorumlardaki sayı görselde ölçülen pikseldir.
///
/// Genişlik neden 360 değil: 360 pt'de oran 0,292 oluyordu ve görselin en
/// küçük yazıları 6,5-7 pt'ye düşüyordu — okunmuyorlardı. Puntoları tek tek
/// yukarı çekmek tasarımın oranlarını bozuyordu. 480 pt'de aynı oran
/// korunarak en küçük yazı 9 pt'ye çıkıyor, yani tasarım birebir uygulanmış
/// oluyor. Cüzdanın yan yana etiket+rozet sütunu da ancak burada sığıyor.
enum PopoverLayout {
    /// 480'den 450'ye indi. Puntolar ve boşluklar DEĞİŞMEDİ; yalnızca çerçeve
    /// daraldı. Kazanç cüzdandan geldi: rozet sütunu kartın sağ kenarına
    /// yaslı olduğu için kart daralınca etiketler de sola geliyor ve ortada
    /// boşa duran alan kapanıyor.
    static let width: CGFloat = 450

    /// 27 px.
    static let outerPadding: CGFloat = 10.5
    /// 22 px. Yatayda ve dikeyde aynı.
    static let cardSpacing: CGFloat = 8.6
    /// 36 px.
    static let cardPadding: CGFloat = 14
    static let cardTopPadding: CGFloat = 14
    /// 29 px.
    static let cardCornerRadius: CGFloat = 11.3

    static var cardWidth: CGFloat { width - outerPadding * 2 }

    /// Rozet 85×85 px, satırın en uzun ögesi.
    static let headerHeight: CGFloat = 33
    static let appMarkSize: CGFloat = 33
    static let appMarkRadius: CGFloat = 8.5
    /// Yenile hapı 70 px yüksekliğinde; başlıktaki dört denetim aynı boyda.
    static let headerControlHeight: CGFloat = 27.3
    /// Başlık şeridi kart kenarından 17 px daha dışarıda başlıyor.
    static let headerInset: CGFloat = 6.6

    /// Halka dış çapı 288 px.
    static let donutSize: CGFloat = 112
    /// Görselde 32 px = 12,5 pt. Kullanıcı "çok az daha ince" dedi: 11,5.
    static let donutLineWidth: CGFloat = 11.5

    /// Çizim alanı 167 px.
    static let chartHeight: CGFloat = 65
    /// Ölçek sütunu + araboşluk 59 px = 23 pt; "100" 9,1 pt eş genişlikli
    /// rakamla 18,1 pt yer kaplıyor.
    static let yAxisWidth: CGFloat = 19
    static let yAxisGap: CGFloat = 4

    // MARK: Saat ısı şeridi
    /// 68 px.
    static let heatStripHeight: CGFloat = 26.5
    /// Hücre adımının %10,1'i (38 px hücre, 4,3 px aralık).
    static let heatGapRatio: CGFloat = 0.101
    /// 12 px.
    static let heatCellRadius: CGFloat = 4.7
    /// Tepe etiketinden hücreye inen çizgi 18 px.
    static let heatTickHeight: CGFloat = 7
    /// Etiket tabanı ile çizgi arası 8 px.
    static let heatTickGap: CGFloat = 3.1

    /// İnce çubuk 24 px.
    static let slimBarHeight: CGFloat = 9.4
    /// Durum rozeti 51 px.
    static let statusPillHeight: CGFloat = 19.9

    // MARK: Ölçülen dikey boşluklar
    //
    // Görseldeki TABAN ÇİZGİSİ aralıklarından, San Francisco'nun satır kutusu
    // payları (ascender-cap üstü, baseline altı) çıkarılarak bulundu.

    /// Kart üstü 22 px, altı 38 px.
    static let limitCardTopPadding: CGFloat = 8.6
    static let limitCardBottomPadding: CGFloat = 14.8
    /// Sekme hapı altı → halka üstü. Görselde 16 px = 6,2 pt; sekme hapı
    /// oradakinden alçak olduğu için o boşluk sıkışık duruyordu.
    static let tabToBodyGap: CGFloat = 12
    /// Halka ile grafik sütunu arası 77 px.
    static let donutToChartGap: CGFloat = 30
    /// "Kullanım geçmişi" tabanı → 100 çizgisi 41 px.
    static let chartTitleGap: CGFloat = 13.4
    /// 0 çizgisi → x ekseni büyük harf üstü 25 px.
    static let chartAxisGap: CGFloat = 7.3

    /// Yarım kartların üstü 34 px, altı 41 px.
    static let dataCardTopPadding: CGFloat = 13.2
    /// Tarih satırının ALTINDAKİ boşluk. Üstündekiyle eşitlendi: ölçülen
    /// değerler üstte 11,5 pt, altta 14,0 pt idi.
    static let dataCardBottomPadding: CGFloat = 13.1
    /// Başlık tabanı → kahraman sayının büyük harf üstü 36 px.
    static let titleToHeroGap: CGFloat = 4.3
    /// Kahraman tabanı → çubuk üstü 23 px.
    static let heroToBarGap: CGFloat = 3.4
    /// Tarih satırının ÜSTÜNDEKİ boşluk. Alttakiyle eşit olacak şekilde
    /// seçildi; esnek boşluk artık burada değil BAŞLIĞIN ALTINDA, yani bu
    /// aralık iki kartta da aynı ve sabit.
    static let barToMetaGap: CGFloat = 11.1
    /// Cüzdandaki iki rozet satırı arası 63 px taban aralığı.
    static let pillRowGap: CGFloat = 4.6

    /// Saat kartının üstü 38 px, altı 37 px.
    static let hoursCardTopPadding: CGFloat = 14.8
    static let hoursCardBottomPadding: CGFloat = 14.4

    /// Yan yana iki kart eşit değil: Fable 507 px, Cüzdan 650 px.
    /// Cüzdan iki rozet sütunu taşıdığı için geniş.
    /// Cüzdan payı 0,562'den 0,60'a çıktı: kart daralınca "Kredi Kullanımı +
    /// rozet" satırı sınıra dayanıyordu. Fable'ın en geniş hâli ("%100
    /// kullanıldı" 125 pt) 0,40 payda 11 pt boşlukla sığıyor.
    static var narrowCardWidth: CGFloat { (cardWidth - cardSpacing) * 0.40 }
    static var wideCardWidth: CGFloat { cardWidth - cardSpacing - narrowCardWidth }
}

/// Punto ölçeği: mockup'tan ölçülen büyük harf yükseklikleri, 0,389610 pt/px
/// oranı ve San Francisco'nun cap/em oranı (0,70459) ile puntoya çevrildi.
/// Yorumdaki sayı görselde ölçülen cap yüksekliğidir.
enum Typo {
    /// "Claude Limit" cap 37 px.
    static let title        = Font.system(size: 20.5, weight: .bold)
    /// "Fable" · "Cüzdan" · "En Aktif Saatler" cap 23,5 px.
    static let cardTitle    = Font.system(size: 13, weight: .bold)
    /// Halkanın içindeki yüzde, cap 52 px.
    static let donutValue   = Font.system(size: 28.5, weight: .bold).monospacedDigit()
    /// Halkanın içindeki "kullanıldı", cap 22 px.
    static let donutCaption = Font.system(size: 12)
    /// Kahraman sayılar, cap 47,5 px.
    static let heroValue    = Font.system(size: 26, weight: .bold).monospacedDigit()
    /// Kahraman sayının etiketi, cap 20 px.
    static let heroLabel    = Font.system(size: 11)
    /// "Kullanım geçmişi", cap 22 px.
    static let chartTitle   = Font.system(size: 12, weight: .semibold)
    /// Hız çarpanı ve rozet etiketleri, cap 18 px.
    static let rateValue    = Font.system(size: 10).monospacedDigit()
    /// Durum rozetinin içi, cap 17 px.
    static let badge        = Font.system(size: 9.5, weight: .semibold)
    /// Grafik eksenleri, cap 16,5 px. Ölçeğin en küçük değeri.
    static let axis         = Font.system(size: 9)
    /// Kart altı meta satırı, cap 18,5 px.
    static let footnote     = Font.system(size: 10)
    static let body         = Font.system(size: 11.5)
    /// Sekme çipi, cap 21,5 px.
    static let tab          = Font.system(size: 12, weight: .semibold)
    /// Isı şeridinin tepe etiketi, cap 15 px = 8,3 pt; ölçeğin 9 pt tabanına
    /// yuvarlandı.
    static let heatPeak     = Font.system(size: 9, weight: .semibold).monospacedDigit()
}

/// Palet: tek bir sıcak nötr taban ve onun üstünde pastel vurgular.
///
/// Önceki palet görselden birebir örneklenmişti ama kendi içinde çatışıyordu:
/// zemin SOĞUK bir mavi-gri (#EFF5F9), ısı şeridi SICAK terracotta, Fable
/// indigo, rozetler ayrı bir yeşil. Dört ayrı renk ailesi tek ekranda
/// buluşunca hiçbiri diğerine ait görünmüyordu.
///
/// Kural şu: TEK sıcak nötr zemin (#F5F3F1 ailesi) ve üstünde AYNI doygunluk
/// (%28-38) ve parlaklık (%62-72) bandındaki pastel vurgular. Isı şeridi ayrı
/// bir skala değil, markanın terracotta'sının zemine doğru açılmış hâli;
/// böylece kartın içindeki en büyük renk lekesi sayfanın geri kalanıyla aynı
/// aileden geliyor.
enum Palette {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static func hex(_ v: UInt32) -> NSColor {
        srgb(Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
    }

    // MARK: Nötr taban

    /// Popover zemini: sıcak nötr, soğuk mavi-gri değil.
    ///
    /// Camın altındaki TABAN rengi. Üstüne `GlassBackdrop` yumuşak renk
    /// lekeleri koyuyor; cam kartlar bulanıklaştırdıkları şey işte o.
    /// Kartların dışındaki alan: açık nötr gri.
    ///
    /// Kartlar BEYAZ olduğu için zemin onlardan bir tık koyu olmak zorunda,
    /// yoksa kart bitip zemin nerede başlıyor okunmuyor. Ölçülen fark %8:
    /// beyaz (L 0,96) ve zemin (L 0,89). Daha da açık bir zemin kartı
    /// kaybediyor, daha koyu olan "gri kutu" hissi veriyor.
    static let popoverBase = dynamic(light: hex(0xEFF0F3), dark: hex(0x141416))
    /// Cam kullanılamadığında (ekran dışı render) kartın düz karşılığı.
    static let cardSurface = dynamic(light: hex(0xFCFCFD), dark: hex(0x232326))

    // MARK: Cam katmanı
    //
    // Cam üç şeyin üst üste binmesi: ARKAYI BULANIKLAŞTIRAN bir katman,
    // üstünde yarı saydam bir ton, ve kenarında ışığı yakalayan ince bir
    // pervaz. Üçü olmadan "yarı saydam kutu" oluyor, cam olmuyor.

    /// Bulanıklığın üstündeki yarı saydam ton. Metin kontrastını bu taşıyor:
    /// tonsuz bulanıklıkta renkli lekeler metnin altından geçiyor.
    /// Kartlar BEYAZ. Açık temada ton tam opak: zeminin rengi kartın içinden
    /// geçtiğinde kart beyaz değil "renkli cam" oluyordu. Camlık artık
    /// pervaz, gölge ve zeminin kendi rengiyle taşınıyor.
    static let glassTint = dynamic(
        light: NSColor(white: 1, alpha: 1.0),
        dark: NSColor(white: 1, alpha: 0.065)
    )
    /// Pervazın üst kenarı (ışığın vurduğu yer) ve alt kenarı.
    /// Pervaz. Kart beyaz olunca beyaz bir pervazın görevi kalmıyor; açık
    /// temada kenar çok hafif bir GRİ çizgiye dönüştü, yalnızca kartın
    /// sınırını tanımlıyor. Koyu temada hâlâ ışık.
    static let glassRimHigh = dynamic(
        light: NSColor(srgbRed: 0.82, green: 0.83, blue: 0.86, alpha: 0.55),
        dark: NSColor(white: 1, alpha: 0.16)
    )
    static let glassRimLow = dynamic(
        light: NSColor(srgbRed: 0.82, green: 0.83, blue: 0.86, alpha: 0.35),
        dark: NSColor(white: 1, alpha: 0.03)
    )
    /// Üst kenardaki iç ışık. Açık temada kart zaten beyaz, üstüne ışık
    /// koymanın anlamı yok ve kabartma hissi veriyordu: sıfır.
    static let glassSheen = dynamic(
        light: NSColor(white: 1, alpha: 0),
        dark: NSColor(white: 1, alpha: 0.055)
    )
    /// Kartın zeminden ayrılmasını sağlayan yumuşak gölge.
    /// Gölge HAFİFLEDİ. %13 opaklık ve 10 pt yarıçap kartları zeminden
    /// "kaldırıyor" ve kabartma (3B) hissi veriyordu; %6 ve 6 pt yalnızca
    /// kartın nerede bittiğini söylüyor.
    static let glassShadow = dynamic(
        light: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.26, alpha: 0.06),
        dark: NSColor(white: 0, alpha: 0.34)
    )
    /// Küçük denetimler (başlık düğmeleri, rozetler, sekme çipi) için daha
    /// yoğun ton: 22 pt'lik bir kapsülde 0,56'lık ton yeterince ayrışmıyor.
    /// Başlıktaki denetimler de kartlarla aynı beyaz.
    static let glassChipTint = dynamic(
        light: NSColor(white: 1, alpha: 1.0),
        dark: NSColor(white: 1, alpha: 0.11)
    )

    /// Zemindeki renk lekeleri. Pastel ve çok düşük opaklıkta: camın
    /// bulanıklaştıracağı bir doku olmadan cam düz bir yüzeye benziyor.
    static let bloomWarm = dynamic(light: hex(0xC8A08F), dark: hex(0xC08B74))
    /// Lekelerin gücü. Camın taşıyacağı renk buradan geliyor: çok düşükte
    /// kartlar yarı saydam gri kutulara dönüşüyor, çok yüksekte zemin
    /// metnin altından bağırıyor.
    /// Lekeler ARTIK ÇOK SOLUK. Zemin nötr gri okunmalı; renk yalnızca camın
    /// altında bir hareket olduğunu belli edecek kadar var. Yüksek opaklıkta
    /// beyaz kartların içinden geçip metnin altını renklendiriyordu.
    static let bloomStrength: [Double] = [0.16, 0.14, 0.13, 0.11]
    static let bloomViolet = dynamic(light: hex(0xA9A2C6), dark: hex(0x9088BC))
    static let bloomSage = dynamic(light: hex(0x9CBCA7), dark: hex(0x78A98A))
    static let bloomBlue = dynamic(light: hex(0x9DB2C9), dark: hex(0x7399C2))

    /// Metin de nötr sıcak: saf gri, sıcak zeminde mavimsi okunuyordu.
    static let primaryText = dynamic(light: hex(0x26262A), dark: hex(0xF1F1F3))
    static let secondaryText = dynamic(light: hex(0x64646C), dark: hex(0xA4A4AC))
    static let tertiaryText = dynamic(light: hex(0x93939C), dark: hex(0x76767E))

    // MARK: Pastel vurgular
    //
    // Dördü de aynı bantta: doygunluk %28-38, parlaklık %62-72. Yan yana
    // durduklarında biri diğerinden daha "yüksek sesli" değil.

    /// HAFTALIK pencere: markanın terracotta'sının pastel hâli.
    static let claudeOrange = dynamic(light: hex(0xCC9E8C), dark: hex(0xC79079))
    static let claudeOrangeTrack = dynamic(light: hex(0xEBDED8), dark: hex(0x342B27))
    static let claudeOrangeLine = dynamic(light: hex(0xC08D79), dark: hex(0xD09A83))
    static let claudeOrangeSoft = dynamic(light: hex(0xF7F1EE), dark: hex(0x272120))
    static let claudeOrangeChip = dynamic(light: hex(0xF1E6E1), dark: hex(0x3B302B))
    static let claudeOrangeInk = dynamic(light: hex(0x8C5238), dark: hex(0xE0AE95))

    /// 5 saatlik pencere: pastel mavi, aynı bantta.
    static let fiveHour = dynamic(light: hex(0x97B0C8), dark: hex(0x7C9CBE))
    static let fiveHourTrack = dynamic(light: hex(0xDFE6EE), dark: hex(0x232B33))
    static let fiveHourLine = dynamic(light: hex(0x85A2BE), dark: hex(0x8FAFD0))
    static let fiveHourSoft = dynamic(light: hex(0xF2F5F8), dark: hex(0x1E242B))
    static let fiveHourChip = dynamic(light: hex(0xE7EDF3), dark: hex(0x28323C))
    static let fiveHourInk = dynamic(light: hex(0x3D6182), dark: hex(0xA3C0DA))

    /// Fable: pastel lavanta. İndigo bu zeminde tek başına parlıyordu.
    static let violet = dynamic(light: hex(0xA8A1C4), dark: hex(0x9089B4))
    static let violetTrack = dynamic(light: hex(0xE0DDEB), dark: hex(0x2A2734))
    static let violetSoft = dynamic(light: hex(0xF1F0F6), dark: hex(0x2D2A38))
    static let violetInk = dynamic(light: hex(0x5F5596), dark: hex(0xB0A8D2))

    /// Olumlu durum: pastel adaçayı.
    static let green = dynamic(light: hex(0x97BAA5), dark: hex(0x7BA88C))
    static let greenSoft = dynamic(light: hex(0xE2EDE6), dark: hex(0x212D25))
    static let greenInk = dynamic(light: hex(0x41754F), dark: hex(0x8FC3A2))

    /// Nötr rozet: zeminle aynı sıcak aileden.
    static let neutralPill = dynamic(light: hex(0xE4E4EB), dark: hex(0x313136))
    /// Sekme hapının izi: seçili çipin çevresindeki nötr yatak.
    static let tabTrack = dynamic(light: hex(0xE2E2EA), dark: hex(0x2B2B31))

    static let blue = fiveHour
    static let blueTrack = fiveHourTrack
    static let blueSoft = fiveHourSoft

    /// Uyarı ve tehlike de PASTELE çekildi: sistem turuncusu/kırmızısı bu
    /// zeminde bağırıyordu. Yine de bandın üst ucunda duruyorlar, çünkü
    /// işlevleri dikkat çekmek.
    static let warning = dynamic(light: hex(0xC49A66), dark: hex(0xD1A472))
    static let critical = dynamic(light: hex(0xBF8383), dark: hex(0xCD8D8D))

    /// Kartların çizgisi yok; ayrımı yüzey farkı taşıyor.
    static let cardBorder = Color.clear
    static let separator = dynamic(light: hex(0xE2E2E8), dark: hex(0x353539))

    static let previewBackdrop = dynamic(light: hex(0xDFE0E5), dark: hex(0x101012))
    static let cardFallback = cardSurface

    /// Isı şeridi: kart yüzeyinden markanın terracotta'sına.
    ///
    /// Ayrı bir "ısı haritası paleti" değil; skalanın BAŞLANGICI kart
    /// yüzeyine, BİTİŞİ haftalık vurguya bağlı. Kartın içindeki en büyük renk
    /// lekesi bu yüzden sayfanın geri kalanına ait görünüyor.
    ///
    /// İki ramp var, çünkü tek ramp koyu temada ters okunuyordu: açık bej
    /// başlangıç koyu kartın üstünde en parlak leke oluyor ve göz "en yoğun
    /// saat" diye BOŞ saatlere gidiyordu. Her iki temada da kural aynı:
    /// sıfır zemine karışır, tepe öne çıkar.
    private static let heatLight: [(Double, UInt32)] = [
        (0.00, 0xF4EFEB), (0.30, 0xEFDDD2), (0.55, 0xE3C2AF),
        (0.80, 0xD3A28A), (1.00, 0xC08668),
    ]
    private static let heatDark: [(Double, UInt32)] = [
        (0.00, 0x2A2A2D), (0.30, 0x3E332F), (0.55, 0x5E463B),
        (0.80, 0x8A5E48), (1.00, 0xB8836B),
    ]

    private static func sample(_ stops: [(Double, UInt32)], _ t: Double) -> NSColor {
        var lower = stops[0], upper = stops[stops.count - 1]
        for i in 1..<stops.count where stops[i].0 >= t {
            lower = stops[i - 1]; upper = stops[i]; break
        }
        let span = upper.0 - lower.0
        let f = span > 0 ? (t - lower.0) / span : 0
        func comp(_ v: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((v >> shift) & 0xFF) / 255 }
        return NSColor(
            srgbRed: comp(lower.1, 16) + (comp(upper.1, 16) - comp(lower.1, 16)) * f,
            green: comp(lower.1, 8) + (comp(upper.1, 8) - comp(lower.1, 8)) * f,
            blue: comp(lower.1, 0) + (comp(upper.1, 0) - comp(lower.1, 0)) * f,
            alpha: 1
        )
    }

    static func heat(_ ratio: Double) -> Color {
        let t = min(max(ratio, 0), 1)
        return dynamic(light: sample(heatLight, t), dark: sample(heatDark, t))
    }

    /// Tepe saatin işaret çizgisi.
    static let heatTick = dynamic(light: hex(0x87878F), dark: hex(0xABABB3))

    /// Projeksiyon: pastel gül. Ölçülmüş geçmişten ayrılmalı ama alarm
    /// çalmamalı; kesikli çizgi zaten "bu tahmin" diyor.
    static let projection = dynamic(light: hex(0xB87B78), dark: hex(0xCF908D))

    /// Hız çarpanının rengi. 1× normal tempo, üstü giderek ısınır.
    static func pace(_ multiplier: Double) -> Color {
        let t = min(max((multiplier - 1) / 1.5, 0), 1)
        guard t > 0 else { return secondaryText }
        return dynamic(
            light: blend(from: hex(0x64646C), to: hex(0xB87B78), t: t),
            dark: blend(from: hex(0xA4A4AC), to: hex(0xCF908D), t: t)
        )
    }

    private static func blend(from: NSColor, to: NSColor, t: Double) -> NSColor {
        let a = from.usingColorSpace(.sRGB) ?? from
        let b = to.usingColorSpace(.sRGB) ?? to
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: 1
        )
    }

    static let criticalThreshold: Double = 90

    static func accent(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical : kind.base
    }

    static func track(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical.opacity(0.18) : kind.track
    }

    static func line(for kind: WindowAccent, usedPercent: Double) -> Color {
        usedPercent >= criticalThreshold ? critical : kind.line
    }
}

enum WindowAccent {
    case fiveHour
    case sevenDay
    case blue
    case green

    /// Halka dolgusu.
    var base: Color {
        switch self {
        case .fiveHour: Palette.fiveHour
        case .sevenDay: Palette.claudeOrange
        case .blue: Palette.blue
        case .green: Palette.green
        }
    }

    /// Halkanın izi.
    var track: Color {
        switch self {
        case .fiveHour: Palette.fiveHourTrack
        case .sevenDay: Palette.claudeOrangeTrack
        case .blue: Palette.blueTrack
        case .green: Palette.greenSoft
        }
    }

    /// Grafik eğrisi: görselde halkadan bir tık koyu (#D98D72 / #DD9D85).
    var line: Color {
        switch self {
        case .fiveHour: Palette.fiveHourLine
        case .sevenDay: Palette.claudeOrangeLine
        case .blue: Palette.fiveHourLine
        case .green: Palette.green
        }
    }

    /// Eğrinin altındaki alan dolgusu.
    var soft: Color {
        switch self {
        case .fiveHour: Palette.fiveHourSoft
        case .sevenDay: Palette.claudeOrangeSoft
        case .blue: Palette.blueSoft
        case .green: Palette.greenSoft
        }
    }

    /// Seçili sekme çipinin zemini.
    var chip: Color {
        switch self {
        case .fiveHour, .blue: Palette.fiveHourChip
        case .sevenDay: Palette.claudeOrangeChip
        case .green: Palette.greenSoft
        }
    }

    /// Seçili sekme çipinin metni.
    var ink: Color {
        switch self {
        case .fiveHour, .blue: Palette.fiveHourInk
        case .sevenDay: Palette.claudeOrangeInk
        case .green: Palette.greenInk
        }
    }
}

/// Kart yüzeyi.
///
/// macOS 26'da Liquid Glass, öncesinde `.regularMaterial`. İkisi de opak beyaz
/// yerine arkasındaki masaüstünü örnekleyen malzemeler, yani kart popover'ın
/// cam zeminiyle aynı dili konuşuyor. Üst iç boşluk yandan az: başlıklar
/// kutunun tepesine daha yakın otursun diye.
struct MetricCard<Content: View>: View {
    var width: CGFloat = PopoverLayout.cardWidth
    /// Dikey iç boşluklar karta göre DEĞİŞİYOR: görselde üç kartın üst ve alt
    /// payları birbirinden farklı (6,5/11,2 · 7,4/10,4 · 8,6/9,4 pt). Tek bir
    /// değere yuvarlamak üç kartın da dikey ritmini kaydırıyordu.
    var topPadding: CGFloat = PopoverLayout.cardTopPadding
    var bottomPadding: CGFloat = PopoverLayout.cardPadding
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PopoverLayout.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .padding(.horizontal, PopoverLayout.cardPadding)
            .frame(width: width, alignment: .leading)
            .modifier(CardSurface(shape: shape))
    }
}

private struct CardSurface: ViewModifier {
    let shape: RoundedRectangle

    /// Cam üç katman: yarı saydam TON, üst kenarda İÇ IŞIK, çevrede
    /// yön taşıyan PERVAZ; hepsinin altında zeminin renk lekeleri geçiyor.
    ///
    /// Arkayı bulanıklaştıran bir `NSVisualEffectView` KULLANILMIYOR ve bu
    /// bilinçli. Camın altında duran tek şey `GlassBackdrop`, o da zaten
    /// yumuşak radyal lekelerden oluşuyor: yumuşak bir gradyanın bulanığı
    /// yine kendisi, yani katman görüntüye ölçülebilir bir şey eklemiyordu.
    /// Buna karşılık üç maliyeti vardı — `ImageRenderer` onu çizemediği için
    /// tasarım turları körleşiyordu, `NSGlassEffectView` odak kaybında
    /// soluklaşıyordu ve pencere ardı harmanlamada popover'ın tonu arkadaki
    /// masaüstüne göre oynuyordu (bu üçüncüsü daha önce ölçülüp opak zemine
    /// geçilmesinin sebebiydi).
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(Palette.glassTint)
                    shape.fill(
                        LinearGradient(
                            colors: [Palette.glassSheen, .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                }
            }
            // Pervaz: üstte ışık, altta neredeyse yok. Tek renk bir kenarlık
            // camı "çerçeveli kutu" yapıyordu; ışığın geldiği yönü taşıyan
            // gradyan onu cam kenarı gibi okutuyor.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Palette.glassRimHigh, Palette.glassRimLow],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            )
            .shadow(color: Palette.glassShadow, radius: 6, y: 1.5)
    }
}

/// Popover'ın zemini: taban rengi ve üstünde yumuşak renk lekeleri.
///
/// Cam, ARKASINDAKİ dokuyu bulanıklaştırarak var oluyor. Düz tek renk bir
/// zeminin bulanığı yine aynı düz renk olduğu için kartlar yarı saydam
/// kutulara dönüşüyordu. Lekeler paletteki dört pastel vurgudan geliyor ve
/// çok düşük opaklıkta: zemin hâlâ nötr okunuyor ama camın kıracağı bir şey
/// var.
struct GlassBackdrop: View {
    var body: some View {
        Palette.popoverBase
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack {
                        bloom(Palette.bloomWarm, Palette.bloomStrength[0])
                            .frame(width: w * 1.1, height: w * 1.1)
                            .position(x: w * 0.18, y: h * 0.06)
                        bloom(Palette.bloomViolet, Palette.bloomStrength[1])
                            .frame(width: w * 0.95, height: w * 0.95)
                            .position(x: w * 1.02, y: h * 0.30)
                        bloom(Palette.bloomBlue, Palette.bloomStrength[2])
                            .frame(width: w * 1.0, height: w * 1.0)
                            .position(x: w * 0.85, y: h * 0.96)
                        bloom(Palette.bloomSage, Palette.bloomStrength[3])
                            .frame(width: w * 0.85, height: w * 0.85)
                            .position(x: w * -0.05, y: h * 0.72)
                    }
                }
            }
            .clipped()
    }

    private func bloom(_ color: Color, _ strength: Double) -> some View {
        Circle().fill(
            RadialGradient(
                colors: [color.opacity(strength), color.opacity(0)],
                center: .center, startRadius: 0, endRadius: 140
            )
        )
    }
}

/// Küçük cam yüzey: düğmeler, rozetler, sekme çipi.
///
/// Kartla aynı üç katman (ton · pervaz · gölge) ama bulanıklık katmanı yok:
/// 22 pt'lik bir kapsülde `NSVisualEffectView` başına bir görünüm eklemek
/// pahalı ve o boyutta bulanıklık zaten okunmuyor. `tint` verilirse ton
/// onun üstüne biniyor (rozetlerin renkli hâli).
private struct GlassChip<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var highlighted: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(Palette.glassChipTint)
                    if let tint { shape.fill(tint) }
                    shape.fill(Palette.primaryText.opacity(highlighted ? 0.07 : 0))
                }
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Palette.glassRimHigh, Palette.glassRimLow],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
            )
            // GÖLGE YOK. Küçük kapsüllerde gölge kabartma (3B) hissi veriyor:
            // "Mevcut / Haftalık" ve "Açık / Kapalı" düğme gibi değil, ETİKET
            // gibi okunmalı. Kenarı yalnızca ince pervaz tanımlıyor.
    }
}

extension View {
    func glassChip<S: InsettableShape>(_ shape: S, tint: Color? = nil,
                                       highlighted: Bool = false) -> some View {
        modifier(GlassChip(shape: shape, tint: tint, highlighted: highlighted))
    }
}

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
/// erişilebilirlik gereği. Animasyon eklendiği anda bu denetim de zorunlu
/// hale geliyor: eskiden kod tabanında hiç hareket olmadığı için gerekmiyordu.
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
