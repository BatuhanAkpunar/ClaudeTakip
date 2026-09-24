import SwiftUI
import AppKit

/// Palet: tek bir sıcak nötr taban ve onun üstünde pastel vurgular.
///
/// Görselden birebir örneklenen renkler kendi içinde çatışır: zemin SOĞUK bir
/// mavi-gri (#EFF5F9), ısı şeridi SICAK terracotta, Fable indigo, rozetler
/// ayrı bir yeşil. Dört ayrı renk ailesi tek ekranda buluşunca hiçbiri
/// diğerine ait görünmez.
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

    private static func hex(_ v: UInt32) -> NSColor {
        NSColor.srgb255(Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
    }

    // MARK: Nötr taban

    /// Panelin camı: `NSPopover`'ın kendi `.behindWindow` malzemesinin
    /// ÜSTÜNDEKİ ince yıkama, opak bir taban değil. Bulanıklık sistemden
    /// geliyor; bu dolgunun işi onu bastırmadan uygulamaya kendi sıcak nötr
    /// kimliğini vermek.
    ///
    /// Alfası KONTRAST GÜVENCESİ. Kartın toplam geçirgenliği
    /// `r = (1 - glassTint.alpha) × (1 - popoverBase.alpha)` ve okunabilirlik
    /// hesabının tamamı bu tek sayıya dayanıyor: bugün r = 0,70 × 0,30 = 0,21,
    /// yani masaüstünün beşte biri metnin altına ulaşıyor. Camlığın bedeli
    /// `secondaryText`in koyulaşması oldu; hesap orada.
    static let popoverBase = dynamic(
        light: NSColor(srgbRed: 0.949, green: 0.941, blue: 0.929, alpha: 0.70),
        dark: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.064, alpha: 0.80)
    )
    /// "Saydamlığı Azalt" açıkken zeminin opak karşılığı.
    static let popoverBaseOpaque = dynamic(light: hex(0xE9E6E2), dark: hex(0x131315))
    /// Saydamlık kapalıyken (ve ekran dışı render'da) kartın düz karşılığı.
    static let cardSurface = dynamic(light: hex(0xFBFAF8), dark: hex(0x232326))

    // MARK: Cam katmanı
    //
    // Cam üç şeyin üst üste binmesi: ARKAYI BULANIKLAŞTIRAN bir katman,
    // üstünde yarı saydam bir ton, ve kenarında ışığı yakalayan ince bir
    // pervaz. Üçü olmadan "yarı saydam kutu" oluyor, cam olmuyor.

    /// Kart dolgusu: panelin üstünde ince bir aydınlanma, beyaz bir kutu değil.
    /// Kartı asıl tanımlayan şey dolgu değil PERVAZ.
    static let glassTint = dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)
    )
    /// Pervaz. Cam yüzeyi tanımlayan ASIL şey bu: dolgu %30'da kendi başına bir
    /// sınır çizmiyor, kenardaki ışık çiziyor.
    ///
    /// Üst kenar ışık, alt kenar GÖLGE — ikisi de düşük alfada. Alt kenarı da
    /// beyaz yapmak denendi ve ölçüldü: parlak bir duvar kağıdında kart yüzeyi
    /// zaten L 0,94'e çıkıyor, beyaz bir alt pervaz orada 1,02:1 kalıyor, yani
    /// YOK; kartın alt ve yan kenarını tek başına gölge taşır. %14'lük koyu
    /// bir alt kenar her iki uçta da ~1,3:1 veriyor; üstelik yukarıdan ışık alan
    /// bir cam kenarının alt tarafı gerçekten koyudur.
    static let glassRimHigh = dynamic(
        light: NSColor(white: 1, alpha: 0.85),
        dark: NSColor(white: 1, alpha: 0.22)
    )
    static let glassRimLow = dynamic(
        light: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.20, alpha: 0.14),
        dark: NSColor(white: 1, alpha: 0.08)
    )
    /// Üst kenardaki iç ışık: camın kalınlığını gösteren şey.
    static let glassSheen = dynamic(
        light: NSColor(white: 1, alpha: 0.20),
        dark: NSColor(white: 1, alpha: 0.07)
    )
    /// Seçili sekme çipi: kompozisyonun TEK OPAK ögesi.
    ///
    /// Referansta da öyle — her şey yarı saydamken seçili "1×" çipi dolu beyaz.
    /// Cam bir yüzeyde göz bir çıpa arıyor; opak tek öge o çıpa oluyor ve aynı
    /// zamanda "burası tıklanabilir, seçili olan bu" diyor. Üstüne pencerenin
    /// kendi vurgusu (`WindowAccent.chip`) yıkanıyor.
    /// Koyu temada %18 YETMEZ: kart zaten %9 beyaz, çipin %18'i onun
    /// yanında çıpa değil soluk bir lozenj kalır. %26'da çip belirgin
    /// şekilde kalkıyor ve `blueInk` üstünde hâlâ 5,1:1 veriyor — daha
    /// açık bir çip mürekkebi yemeye başlıyor.
    static let chipSolid = dynamic(
        light: NSColor(white: 1, alpha: 0.92),
        dark: NSColor(white: 1, alpha: 0.26)
    )
    /// Kartı zeminden ayıran yumuşak gölge.
    ///
    /// Alfa BİLEREK çok yüksek; ekrandaki değer bunun çok altında.
    ///
    /// `.shadow` kaynağın ALFA MASKESİNİ çiziyor, yani gölge kart dolgusunun
    /// alfasıyla ÇARPILIYOR: 0,43 × 0,30 ≈ 0,13 ekranda çıkan değer. Camda
    /// gölge geniş ve yumuşak olmalı (yarıçap 7), çünkü işi kartı "kaldırmak"
    /// değil, yarı saydam yüzeyin nerede bittiğini söylemek.
    static let glassShadow = dynamic(
        light: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 0.43),
        dark: NSColor(white: 0, alpha: 0.75)
    )
    /// Küçük denetimler (başlık düğmeleri, rozetler) için karttan bir tık
    /// yoğun ton: 22 pt'lik bir kapsülde kartın alfası yeterince ayrışmıyor.
    static let glassChipTint = dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.48),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
    )

    /// Metin de nötr sıcak: saf gri, sıcak zeminde mavimsi okunur.
    ///
    /// İkincil ton camlığın FATURASI, ve fatura İKİ TEMADA AYRI kesiliyor.
    ///
    /// Açık tema: panel %70 iken kartın altına ulaşan masaüstü %21; koyu bir
    /// duvar kağıdında kart yüzeyi sRGB 0,74'e düşüyor ve #5B5B63 orada 3,3:1
    /// verir. #4A4A52 aynı yerde 4,6:1.
    ///
    /// Koyu tema DAHA SERT etkileniyor: beyaz kart dolgusunda geçirgenlik
    /// 0,182 (koyu dolguda 0,064'tü, neredeyse üç katı). BEYAZ bir duvar
    /// kağıdında kart L 0,080'e kadar açılıyor ve #A4A4AC orada 3,7:1 kalır.
    /// #C2C2CA 4,6:1 veriyor ve hâlâ birincil metnin bir kademe altında duruyor.
    static let primaryText = dynamic(light: hex(0x26262A), dark: hex(0xF1F1F3))
    static let secondaryText = dynamic(light: hex(0x4A4A52), dark: hex(0xC2C2CA))
    /// SALT DEKORATİF: ızgara çizgileri, bayat simge tonu. Hiçbir zeminde
    /// 4,5:1'e ulaşmıyor, dolayısıyla okunması gereken hiçbir metin bunu
    /// kullanmamalı.
    static let tertiaryText = dynamic(light: hex(0x83838C), dark: hex(0x8A8A93))

    // MARK: Pastel vurgular
    //
    // Dördü de aynı bantta: doygunluk %28-38, parlaklık %62-72. Yan yana
    // durduklarında biri diğerinden daha "yüksek sesli" değil.
    //
    // KURAL: kartın ÜSTÜNE binen her dolgu (iz, yatak, rozet zemini, alan
    // dolgusu) MUTLAK renk değil, karta GÖRELİ alfa olarak yazılıyor. Kart
    // saydam olduğu için altındaki parlaklık duvar kağıdıyla değişiyor; mutlak
    // bir açık bej, koyu bir duvar kağıdında kartın üstünde parlayan opak bir
    // leke hâline geliyor ve aynı sütundaki göreli komşusuyla farklı dil
    // konuşuyor. Vurgunun KENDİSİ (halka dolgusu, eğri, mürekkep) opak kalıyor:
    // onlar zeminin üstünde okunması gereken şeyler.

    /// HAFTALIK pencere: markanın terracotta'sının pastel hâli.
    static let orange = dynamic(light: hex(0xCC9E8C), dark: hex(0xC79079))
    static let orangeTrack = dynamic(
        light: NSColor(srgbRed: 0.75, green: 0.55, blue: 0.47, alpha: 0.28),
        dark: NSColor(srgbRed: 0.78, green: 0.56, blue: 0.47, alpha: 0.26)
    )
    static let orangeLine = dynamic(light: hex(0xC08D79), dark: hex(0xD09A83))
    static let orangeSoft = dynamic(
        light: NSColor(srgbRed: 0.75, green: 0.55, blue: 0.47, alpha: 0.14),
        dark: NSColor(srgbRed: 0.78, green: 0.56, blue: 0.47, alpha: 0.13)
    )
    static let orangeChip = dynamic(
        light: NSColor(srgbRed: 0.75, green: 0.55, blue: 0.47, alpha: 0.34),
        dark: NSColor(srgbRed: 0.78, green: 0.56, blue: 0.47, alpha: 0.26)
    )
    static let orangeInk = dynamic(light: hex(0x8C5238), dark: hex(0xE0AE95))

    /// 5 saatlik pencere: pastel mavi, aynı bantta.
    static let blue = dynamic(light: hex(0x97B0C8), dark: hex(0x7C9CBE))
    static let blueTrack = dynamic(
        light: NSColor(srgbRed: 0.52, green: 0.63, blue: 0.75, alpha: 0.28),
        dark: NSColor(srgbRed: 0.49, green: 0.61, blue: 0.75, alpha: 0.26)
    )
    static let blueLine = dynamic(light: hex(0x85A2BE), dark: hex(0x8FAFD0))
    static let blueSoft = dynamic(
        light: NSColor(srgbRed: 0.52, green: 0.63, blue: 0.75, alpha: 0.14),
        dark: NSColor(srgbRed: 0.49, green: 0.61, blue: 0.75, alpha: 0.13)
    )
    static let blueChip = dynamic(
        light: NSColor(srgbRed: 0.52, green: 0.63, blue: 0.75, alpha: 0.34),
        dark: NSColor(srgbRed: 0.49, green: 0.61, blue: 0.75, alpha: 0.26)
    )
    static let blueInk = dynamic(light: hex(0x3D6182), dark: hex(0xA3C0DA))

    /// Fable: pastel lavanta. İndigo bu zeminde tek başına parlar.
    static let violet = dynamic(light: hex(0xA8A1C4), dark: hex(0x9089B4))
    static let violetTrack = dynamic(
        light: NSColor(srgbRed: 0.58, green: 0.55, blue: 0.72, alpha: 0.28),
        dark: NSColor(srgbRed: 0.56, green: 0.53, blue: 0.70, alpha: 0.26)
    )
    static let violetInk = dynamic(light: hex(0x5F5596), dark: hex(0xB0A8D2))

    /// Olumlu durum: pastel adaçayı.
    static let green = dynamic(light: hex(0x97BAA5), dark: hex(0x7BA88C))
    /// "Açık" rozetinin zemini. Yanındaki nötr rozet %9'luk bir çukur olduğu
    /// için bu da göreli: opak kalsaydı aynı sütundaki iki rozetten biri
    /// çukur, diğeri parlak bir lozenj olurdu.
    static let greenSoft = dynamic(
        light: NSColor(srgbRed: 0.35, green: 0.55, blue: 0.42, alpha: 0.20),
        dark: NSColor(srgbRed: 0.48, green: 0.66, blue: 0.54, alpha: 0.20)
    )
    static let greenInk = dynamic(light: hex(0x41754F), dark: hex(0x8FC3A2))

    /// Nötr rozet: kartın yüzeyine açılmış bir çukur.
    static let neutralPill = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.09),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)
    )
    /// Sekme hapının izi: seçili çipin çevresindeki oluk.
    static let tabTrack = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )


    /// Uyarı ve tehlike de PASTEL: sistem turuncusu/kırmızısı bu zeminde
    /// bağırır. Yine de bandın üst ucunda duruyorlar, çünkü
    /// işlevleri dikkat çekmek.
    static let warning = dynamic(light: hex(0xC49A66), dark: hex(0xD1A472))
    static let critical = dynamic(light: hex(0xBF8383), dark: hex(0xCD8D8D))

    /// Uyarı ve tehlikenin METİN tonu. Üstteki pasteller yalnızca DOLGU:
    /// parlaklıkları 0,358 ve 0,289, yani BEYAZIN üstünde bile tavanları 2,6:1
    /// ve 3,1:1 — açık temada hangi zemin olursa olsun 4,5:1'e ulaşamıyorlar.
    /// Kart saydamlaşınca oran daha da düştü. Koyu temada pastel zaten yeterli.
    static let warningInk = dynamic(light: hex(0x684311), dark: hex(0xD1A472))
    static let criticalInk = dynamic(light: hex(0x7C2E2E), dark: hex(0xCD8D8D))

    static let separator = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.085),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.11)
    )

    #if DEBUG
    static let previewBackdrop = dynamic(light: hex(0xDFE0E5), dark: hex(0x101012))
    #endif

    /// Isı şeridi: kart yüzeyinden markanın terracotta'sına.
    ///
    /// Bir RENK rampası değil, tek hue üzerinde bir SAYDAMLIK rampası.
    /// Kart saydam olduğu için "sıfır zemine karışır" kuralını ancak böyle
    /// tutabiliyoruz: sıfır hücresi kartın kendi yüzeyinin %6-8'i kadar bir
    /// ton, tepe hücresi tam vurgu. Mutlak renklerle yazılsaydı sıfır hücresi
    /// kartın üstünde kendi başına bir leke olurdu.
    ///
    /// Hue rampa boyunca SABİT: bej'den terracotta'ya giden bir renk
    /// rampasının ara değerleri pembeden geçer.
    private static let heatLight: [(Double, UInt32, CGFloat)] = [
        (0.00, 0xC08668, 0.08), (0.30, 0xC08668, 0.30), (0.55, 0xC08668, 0.56),
        (0.80, 0xBE7E58, 0.80), (1.00, 0xB87A57, 1.00),
    ]
    private static let heatDark: [(Double, UInt32, CGFloat)] = [
        (0.00, 0xC79079, 0.06), (0.30, 0xC79079, 0.26), (0.55, 0xC79079, 0.52),
        (0.80, 0xCA9070, 0.78), (1.00, 0xCE9673, 1.00),
    ]

    private static func sample(_ stops: [(Double, UInt32, CGFloat)], _ t: Double) -> NSColor {
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
            // Alfa da ara değerleniyor: rampanın taşıdığı şey bu.
            alpha: lower.2 + (upper.2 - lower.2) * CGFloat(f)
        )
    }

    static func heat(_ ratio: Double) -> Color {
        let t = min(max(ratio, 0), 1)
        return dynamic(light: sample(heatLight, t), dark: sample(heatDark, t))
    }

    /// Tepe saatin işaret çizgisi. Değişken bir şeridin üstünde duruyor, o
    /// yüzden sabit gri değil göreli.
    static let heatTick = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
    )

    /// Projeksiyon: pastel gül. Ölçülmüş geçmişten ayrılmalı ama alarm
    /// çalmamalı; kesikli çizgi zaten "bu tahmin" diyor.
    static let projection = dynamic(light: roseLight, dark: roseDark)

    /// Pastel gül: projeksiyonun rengi ve hız rampasının sıcak ucu.
    private static let roseLight = hex(0xB87B78)
    private static let roseDark = hex(0xCF908D)

    /// Hız çarpanının rengi. 1× normal tempo, üstü giderek ısınır.
    /// Pace kotaya oran: 1'in üstü sıfırlanmadan dolmak demek. Rampa
    /// 1,0'dan 1,5'e: 1,5× bütçenin bir buçuk katı, yani pencerenin üçte
    /// ikisinde tükeniyorsun.
    static func pace(_ multiplier: Double) -> Color {
        let t = min(max((multiplier - 1) / 0.5, 0), 1)
        guard t > 0 else { return secondaryText }
        // Rampa `secondaryText`in KENDİ tonlarından başlıyor: eski griler
        // (0x64646C / 0xA4A4AC) 4,5:1'in altındaydı ve 1,0×'in hemen üstünde
        // renk bir anda soluklaşıyordu.
        return dynamic(
            light: blend(from: hex(0x4A4A52), to: roseLight, t: t),
            dark: blend(from: hex(0xC2C2CA), to: roseDark, t: t)
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
}
