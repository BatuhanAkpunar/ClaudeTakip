import SwiftUI

/// Ölçüler: mockup oranından değil, ÖLÇÜLEN ihtiyaçtan.
///
/// 1278×1230 px'lik tasarımın tek oranı (0,389610 pt/px) bir SAYFA için
/// doğru; menü çubuğu popover'ı sayfa değil ve HIG'in tek kuralı "popover'ı
/// içeriğini gösterecek kadar büyük yap, daha fazla değil". Her boşluk o
/// orandan değil gerçek ihtiyaçtan kesiliyor (oranla 450×483 pt, ihtiyaçla
/// 420×392 pt).
///
/// Genişlik neden 420: bağlayıcı eşitsizlik
/// `W >= 2·outerPadding + cardSpacing + 4·cardPadding + Fableİçi + Cüzdanİçi`
/// = 16 + 7 + 52 + 122,7 + 212,3 = 410 pt. 420, ölçülen her metin için ~10 pt
/// pay bırakıyor; cüzdan satırında kalan slak 3,9 pt, yani `cardPadding` bir
/// punto daha büyürse o satır taşar.
///
/// Bu eşitsizlik `LabeledPill`in kısa-etiket yedeği çalıştığında geçerli;
/// yedeği `.fixedSize()` bozarsa cüzdan satırı sessizce taşar. Bkz.
/// `WalletContent`.
enum PopoverLayout {
    static let width: CGFloat = 420

    /// Popover kendi yuvarlak çerçevesini zaten çiziyor; dış pay kenar
    /// tanımlamıyor, yalnızca kartları çerçeveden ayırıyor.
    static let outerPadding: CGFloat = 8
    /// Kartların kenarlığı yok; ayrımı yüzey farkı taşıyor. 7 pt'de sayfa dört
    /// ayrı kutu değil TEK gruplanmış panel okunuyor.
    static let cardSpacing: CGFloat = 7
    /// YATAY iç pay. Yan yana iki kart bunu dört kez ödüyor, yani her puntosu
    /// pencere genişliğinden 4 pt götürüyor. `cardCornerRadius`in ALTINA
    /// inemez: `MetricCard` içeriği o şekle kırpıyor.
    static let cardPadding: CGFloat = 13
    static let cardTopPadding: CGFloat = 10
    /// DİKEY alt pay, `cardPadding`ten ayrı: yatay bir sayı dikey payı
    /// belirlerse yatayı sıkmak dikeyi kaydırır.
    static let cardBottomPadding: CGFloat = 11
    /// `MetricCard` içeriği bu şekle kırptığı için `cardPadding`i AŞAMAZ.
    /// Camda yarıçap büyük olmalı: keskin köşe yüzeyi "kesilmiş kağıt", yumuşak
    /// köşe "dökülmüş cam" okutuyor.
    static let cardCornerRadius: CGFloat = 13

    static var cardWidth: CGFloat { width - outerPadding * 2 }

    /// Şeridin boyunu marka rozeti değil DENETİMLER belirliyor.
    static let headerHeight: CGFloat = 27
    static let appMarkSize: CGFloat = 26
    static let appMarkRadius: CGFloat = 7
    /// macOS'un "small" denetim boyu. 10 pt yaş etiketi rahat sığıyor.
    static let headerControlHeight: CGFloat = 22
    /// Başlık şeridinin yatay payı, DOĞRUDAN: `outerPadding`i götüren bir
    /// ifade olursa dış pay değişince başlık kartların ters yönüne kayar.
    static let headerInset: CGFloat = 4

    /// Halkanın içindeki "%100" yazısının gerektirdiği açıklıktan TÜRETİLDİ.
    ///
    /// 20 pt eş genişlikli rakamla dize 56,8 pt geniş, iki satırlık öbek
    /// 36,4 pt yüksek; köşeleri de sayarsak gereken açık yarıçap 33,7.
    /// 88 pt çap ve 8,5 pt çizgi 35,5 veriyor (+1,8 pay).
    static let donutSize: CGFloat = 88
    /// 8,5/88 = 0,097; eski oran 11,5/112 = 0,103. Halkanın görsel ağırlığı
    /// değişmiyor, yalnızca ölçeği düşüyor.
    static let donutLineWidth: CGFloat = 8.5

    /// Halkayla BİRLİKTE iniyor: grafik sütunu kartın boy belirleyicisi olmasın
    /// diye toplamı halkanın altında kalmalı (13,8 + 8 + 46 + 4 + 10,6 = 82,4).
    static let chartHeight: CGFloat = 46
    /// "100" 9 pt eş genişlikli rakamla 18,1 pt yer kaplıyor.
    static let yAxisWidth: CGFloat = 19
    static let yAxisGap: CGFloat = 3

    // MARK: Saat ısı şeridi
    static let heatStripHeight: CGFloat = 21
    /// Hücre adımının %10,1'i.
    static let heatGapRatio: CGFloat = 0.101
    static let heatCellRadius: CGFloat = 4
    /// Tepe etiketinden hücreye inen çizgi.
    static let heatTickHeight: CGFloat = 5.5
    /// Etiket tabanı ile çizgi arası.
    static let heatTickGap: CGFloat = 2.5

    static let slimBarHeight: CGFloat = 7
    /// Durum rozeti. 9,5 pt yazının satır kutusu 11,2 pt; 16 pt kapsül üstte ve
    /// altta 2,4 pt pay bırakıyor.
    static let statusPillHeight: CGFloat = 16

    // MARK: Dikey boşluklar
    //
    // Hepsi ölçülen ihtiyaçtan: bir boşluk ya iki taban çizgisini gözün
    // ayırabilmesi için tutuyor ya da bir gruplama sınırı çiziyor. İkisini de
    // yapmayan pay yok.

    static let limitCardTopPadding: CGFloat = 5
    static let limitCardBottomPadding: CGFloat = 10
    /// Sekme hapı altı → halka üstü.
    static let tabToBodyGap: CGFloat = 8
    /// Halka ile grafik sütunu arası. Kartın kendi iç payının (13 pt) iki
    /// katını aşan bir iç boşluk kartı iki ayrı kart gibi okutur. Halkanın yuvarlak silueti optik payı zaten veriyor.
    static let donutToChartGap: CGFloat = 20
    /// "Kullanım geçmişi" tabanı → 100 çizgisi. Ölçü satır kutusunun ALTINA
    /// kadar; altındaki şey 0,75 pt noktalı bir çizgi.
    static let chartTitleGap: CGFloat = 8
    /// 0 çizgisi → x ekseni.
    static let chartAxisGap: CGFloat = 4

    static let dataCardTopPadding: CGFloat = 7
    static let dataCardBottomPadding: CGFloat = 9
    /// Bölüm etiketi → kahraman sayı. Etiket ve sayı TEK bir öbek okunmalı.
    static let titleToHeroGap: CGFloat = 3
    static let heroToBarGap: CGFloat = 3
    /// Tarih satırının üstündeki boşluk.
    static let barToMetaGap: CGFloat = 8
    static let pillRowGap: CGFloat = 3

    static let hoursCardTopPadding: CGFloat = 7
    static let hoursCardBottomPadding: CGFloat = 9

    /// Yan yana iki kart eşit değil: Cüzdan iki rozet sütunu taşıdığı için
    /// geniş. Pay 0,39 (0,40 değil) — pencere daralınca cüzdanın "etiket +
    /// rozet" satırı kısa hâline düşmesin diye.
    static var narrowCardWidth: CGFloat { (cardWidth - cardSpacing) * 0.39 }
    static var wideCardWidth: CGFloat { cardWidth - cardSpacing - narrowCardWidth }
}
