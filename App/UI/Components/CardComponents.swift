import SwiftUI
import LimitCore

/// Kart başlığı: küçük punto, VERSAL, harf aralığı açık BÖLÜM ETİKETİ.
///
/// Neden 13 pt kalın başlık değil: o başlık kartın en ağır İKİNCİ ögesi olur
/// ve kahraman sayıyla ("%4", "$9,18") ağırlık yarışına girer — göz karta
/// girince önce hangisine bakacağını bilemez. Versal etiket hiyerarşide
/// sayının ALTINA düşüyor, yani sayı hiç büyümeden öne çıkıyor. Satır kutusu
/// 11,8 pt (kalın başlıkta 15,3): kart başına 3,5 pt kazanç.
///
/// Renk: referansta bölüm etiketi vurgu renginde. Burada YAPILMADI, çünkü
/// uygulamanın dört ayrı vurgu ailesi var; "CÜZDAN"ı mavi, "FABLE"ı lavanta
/// yazmak tek ekranda dört renkli başlık demek olurdu.
struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    /// Türkçede "i"nin büyüğü "İ". Yerelden bağımsız `uppercased()`
    /// "EN AKTİF SAATLER" yerine "EN AKTIF SAATLER" üretiyor.
    private var label: String { title.uppercased(with: L.locale) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Typo.sectionLabel)
                .tracking(Typo.sectionLabelTracking)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                // Ekran okuyucu versal metni harf harf hecelemesin.
                .accessibilityLabel(title)

            Spacer(minLength: 6)

            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Ortak kart bileşenleri

/// Görseldeki "etiket + rozet" satırı: solda ne olduğu, sağda hâli.
///
/// Etiket ile rozet arası 15 px → 4,4 pt; etiket "0,3×" ile aynı puntoda
/// (cap 18 px → 7,5 pt).
struct LabeledPill: View {
    let label: String
    /// Tam etiket sığmazsa kullanılan kısa hâl.
    let shortLabel: String
    let text: String
    let fill: Color
    let ink: Color

    var body: some View {
        // Etiket KIRPILMIYOR: sığan hâl çiziliyor. "Tavan doldu" gibi uzun bir
        // durumda rozet 74 pt'ye çıkıyor ve tam etiketle birlikte satır
        // 151 pt oluyor; kartın sağ sütununa düşen yer 123 pt. O nadir durumda
        // etiket kısalıyor, anlamı ipucu taşıyor.
        ViewThatFits(in: .horizontal) {
            row(label)
            row(shortLabel)
            // SON ÇARE: kısa etiket de sığmazsa yalnız rozet. `ViewThatFits`
            // hiçbiri sığmazsa SONUNCUYU çiziyor; sonuncu `row(shortLabel)`
            // olsaydı içindeki `fixedSize` yüzünden kırpılmadan TAŞARDI.
            StatusPill(text: text, fill: fill, ink: ink)
        }
        .help("\(label): \(text)")
        // Ekranda kısa hâle düşülse bile VoiceOver TAM etiketi duyuyor. Sütun
        // gerçekten sıkışabildiği için bu zorunlu.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }

    private func row(_ caption: String) -> some View {
        HStack(spacing: 5) {
            // Etiket `footnote` (10 pt regular), rozetin içi `badge` (9,5 pt
            // semibold): "Kredi Kullanımı" bir ETİKET, "Açık" bir DURUM. İkisi
            // aynı fontta olunca satır tek bir gri şeride dönüşür.
            Text(caption)
                .font(Typo.footnote)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
            StatusPill(text: text, fill: fill, ink: ink)
        }
    }
}

/// Durum rozeti: kısa bir hâlin adı, kendi zemininde.
///
/// Düz metin olarak yazıldığında ("Kapalı") kartın diğer ikincil satırlarıyla
/// aynı ağırlıkta kalır ve bir DURUM olduğu okunmaz. Zemin onu satırdan
/// ayırıyor, renk hangi durum olduğunu söylüyor.
struct StatusPill: View {
    let text: String
    let fill: Color
    let ink: Color

    var body: some View {
        // Görselde "Açık" rozeti 32,7 × 14,9 pt; zemin #E2F1E5, metin #2A7955.
        // Nötr hâlde zemin #E8ECEF, metin #393E48.
        Text(text)
            .font(Typo.badge)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            // Yatay pay 6,5: 16 pt'lik kapsülle orantılı.
            .padding(.horizontal, 6.5)
            .frame(height: PopoverLayout.statusPillHeight)
            // Düz dolgu: rozet bir durumun ADI, basılacak bir yüzey değil.
            .background(Capsule(style: .continuous).fill(fill))
    }
}

/// Kart altındaki meta bilgi: küçük simge + kısa değer.
///
/// "yenilenme 19 Eyl" ve "oto-yükleme açık" gibi düz cümleler kartın en alt
/// satırlarını gereksiz uzatır ve hepsi aynı gri tonda okunmadan geçilir.
/// Simge ne olduğunu söylüyor, renk durumu söylüyor, metin yalnızca değeri
/// taşıyor: üç kanal, tek satır.
struct MetaLine: View {
    let symbol: String
    let text: String
    /// Sığmazsa kullanılan kısa hâl ("29 Eyl"). Kırpılmış bir tarih okunmaz
    /// olduğu için tarih taşıyan çağrılar bunu veriyor.
    var shortText: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(text)
            // `if let` DEĞİL: koşullu bir dal `ViewThatFits`e nil durumunda her
            // zaman sığan boş bir aday verir ve satır tümüyle kaybolur.
            row(shortText ?? text)
        }
        .foregroundStyle(Palette.secondaryText)
    }

    private func row(_ value: String) -> some View {
        HStack(spacing: 3.5) {
            // Simge 9 pt'de KALIYOR: metin 10 pt ve simge ondan küçük olursa
            // satır "takvim mi nokta mı" okunmaz hâle geliyor.
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .regular))
            Text(value)
                .font(Typo.footnote)
                .lineLimit(1)
                // `ViewThatFits` adayı İDEAL boyutundan seçiyor; `fixedSize`
                // ideali tek satırın tam genişliğine sabitliyor, yani kısa hâle
                // düşme kararı ölçüme dayanıyor, kırpmaya değil.
                .fixedSize()
        }
    }
}

/// Dipnot metni: küçük punto, satır kaydırarak uzar (dikeyde ideal boy).
/// Yalnızca bu zincirin birebir aynısı olan yerler kullanıyor; `lineLimit`
/// ya da `fixedSize()` isteyen dipnotlar kendi zincirini koruyor.
struct FootnoteText: View {
    let text: String
    var ink: Color = Palette.secondaryText

    var body: some View {
        Text(text)
            .font(Typo.footnote)
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
