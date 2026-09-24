import SwiftUI
import AppKit

/// Kart yüzeyi: yarı saydam bir dilim.
///
/// Dikey iç boşluklar karta göre ayarlanıyor (bkz. limitCard*/dataCard*/hoursCard*);
/// üç kartın ritmi birbirinin aynısı değil ve tek bir değere yuvarlamak üçünü
/// de kaydırır.
struct MetricCard<Content: View>: View {
    var width: CGFloat = PopoverLayout.cardWidth
    var topPadding: CGFloat = PopoverLayout.cardTopPadding
    var bottomPadding: CGFloat = PopoverLayout.cardBottomPadding
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
            // İçerik kartın dışına çizmesin. Kart genişliği SABİT; kırpma
            // olmazsa `fixedSize` kullanımlarından biri taştığında yazı kartın,
            // hatta popover'ın dışına çizilir ve hiçbir şey uyarmaz. Kırpma `CardSurface`ten ÖNCE, yoksa pervaz ve gölge
            // de kırpılırdı.
            .clipShape(shape)
            .modifier(CardSurface(shape: shape))
    }
}

/// Kart yüzeyi: yarı saydam TON, üst kenarda İÇ IŞIK, çevrede PERVAZ.
///
/// Bulanıklık katmanını BİZ çizmiyoruz ve bu bilinçli. `NSPopover` kendi
/// çerçevesini zaten arkayı bulanıklaştıran bir sistem malzemesiyle çiziyor;
/// üstüne OPAK bir dolgu koymak o malzemeyi gizler. Saydamlık bir katman
/// EKLEYEREK değil, opak dolgu koymayarak geliyor. Pencerede tek bulanıklık katmanı var, en altta;
/// kartlar onun üstünde yalnızca düz renk. İkinci bir malzeme koymak aynı
/// masaüstünü ikinci kez tonlar, yani daha saydam değil daha ÇAMURLU olur.
///
/// Opak zemin lehine üç sebep var, üçünün de karşılığı:
///  (a) `ImageRenderer` malzemeyi çizemiyor → ağaçta `NSVisualEffectView`
///      YOK, yazdığımız her katman düz renk; ekran dışı render ekrandakiyle
///      aynı çiziyor (yalnız popover'ın kendi malzemesi olmadığı için sonuç
///      biraz DAHA kötü, yani önizleme temkinli tarafta yanılıyor).
///  (b) Odak kaybında solma → `StatusItemController.pinNow()` pencerenin KÖK
///      görünümünden başlayarak her malzemeyi `.active`'e sabitliyor; bu
///      tasarımda o kod taşıyıcı.
///  (c) Tonun arkadaki masaüstüne göre oynaması → gerçek saydamlıkta
///      kaçınılmaz, ama ÖLÇÜLÜ: kartın geçirgenliği %21 (bkz. `popoverBase`).
private struct CardSurface: ViewModifier {
    let shape: RoundedRectangle

    /// Sistemdeki "Saydamlığı Azalt" ayarı. Saydam bir arayüzde bunu
    /// desteklemek bir erişilebilirlik gereği.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(reduceTransparency ? Palette.cardSurface : Palette.glassTint)
                    if !reduceTransparency {
                        shape.fill(
                            LinearGradient(
                                colors: [Palette.glassSheen, .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                    }
                }
                // Gölge yalnızca ZEMİNİN. Bütün kompozite uygulansa saydam
                // kartta metnin gölgesi altından sızar. `compositingGroup` iki dolguyu
                // önce düzleştiriyor ki gölge ikisinin BİRLEŞİMİNDEN çıksın.
                .compositingGroup()
                .shadow(color: Palette.glassShadow, radius: 7, y: 2)
            }
            .overlay(shape.glassRim(lineWidth: 0.8))
    }
}

/// Popover'ın zemini: camın ÜSTÜNDEKİ ince yıkama.
///
/// Opak bir TABAN değil. Altında popover'ın kendi sistem malzemesi
/// duruyor ve bulanıklığı buradan geçirmek zorundayız. Yıkamanın iki işi var:
/// masaüstünün rengini bastırıp uygulamaya kendi sıcak nötr kimliğini vermek,
/// ve kartların altındaki geçirgenliği hesaplanabilir bir tavana oturtmak.
///
/// Renk lekesi (radyal doku) YOK: altta gerçek masaüstü var, doku onun. Sabit
/// RENKLİ lekeler rastgele bir duvar kağıdıyla çarpışıp çamur yapar ve
/// saydam kartlarda metnin ALTINI renklendirir. Onun yerine tek bir dikey
/// parlaklık farkı var: renk değil ışık taşıdığı için hangi zeminin üstünde
/// olursa olsun aynı yönü veriyor.
struct GlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        (reduceTransparency ? Palette.popoverBaseOpaque : Palette.popoverBase)
            .overlay {
                LinearGradient(
                    colors: [Palette.glassSheen.opacity(0.6), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
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
    let tint: Color?
    let highlighted: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(reduceTransparency ? Palette.cardSurface : Palette.glassChipTint)
                    if let tint { shape.fill(tint) }
                    shape.fill(Palette.primaryText.opacity(highlighted ? 0.07 : 0))
                }
            }
            .overlay(shape.glassRim(lineWidth: 0.6))
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

    /// Başlık şeridindeki yuvarlak denetim yüzeyi.
    func headerCircleChip(highlighted: Bool = false) -> some View {
        frame(width: PopoverLayout.headerControlHeight,
              height: PopoverLayout.headerControlHeight)
            .glassChip(Circle(), highlighted: highlighted)
    }
}

private extension InsettableShape {
    /// Pervaz: üstte ışık, altta gölge. Tek renk bir kenarlık camı
    /// "çerçeveli kutu" yapar; ışığın yönünü taşıyan gradyan onu cam kenarı
    /// gibi okutuyor. Kart ile aralık arasındaki parlaklık farkı saydam
    /// zeminde %4'e kadar inebildiği için kartın nerede bittiğini söyleyen
    /// iki şeyden biri bu.
    func glassRim(lineWidth: CGFloat) -> some View {
        strokeBorder(
            LinearGradient(
                colors: [Palette.glassRimHigh, Palette.glassRimLow],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: lineWidth
        )
    }
}
