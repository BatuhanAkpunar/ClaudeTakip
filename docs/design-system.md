# Claude Limit | Native macOS Tasarım Spesifikasyonu

**Durum:** karar verilmiş, uygulanabilir
**Tarih:** 22 Ağustos 2026
**Hedef:** macOS 15+ (macOS 26 Tahoe birinci sınıf)
**Girdi:** Apple HIG (DocC JSON), macOS 26.6.2 / build 25G83 üzerinde canlı AppKit probe ölçümleri, 8 açık kaynak menü çubuğu uygulamasının kaynak kodu, 6 Claude kullanım takip uygulamasının kaynak kodu ve issue listesi
**Bağlandığı belge:** `docs/spec-v2.md` (ürün spesifikasyonu). Bu belge spec-v2 §4'ün yerine geçer.

---

## 0. Bu belgenin çalışma kuralı

Her ölçü ya Apple'ın yayınladığı bir sayıdan, ya kullanıcının makinesinde ölçülmüş bir AppKit değerinden, ya da olgun bir uygulamanın kaynak kodundan geliyor. Kaynağı olmayan sayı bu belgeye girmedi.

İki temel kısıt, tüm kararların üstünde:

1. **HIG'in menü çubuğu için verdiği tek sayısal referans 24 pt'dir** (menü çubuğu yüksekliği). Popover genişliği için Apple hiçbir aralık yayınlamıyor. Popovers sayfasının tamamında tek bir pt değeri geçmiyor. Tek kural şu: *"Avoid making a popover too big. Make a popover only big enough to display its contents."* Yani genişlik, içeriğin ölçülmesiyle türetilecek, hazır bir sayı seçilmeyecek.
2. **HIG menü çubuğu ögesi için popover değil menü istiyor:** *"Display a menu, not a popover, when people click your menu bar extra. Unless the app functionality you want to expose is too complex for a menu."* Bizim içeriğimiz (iki grafik, 24 kovalı bar grafik, projeksiyon eğrisi) menü satırlarına sığmaz, dolayısıyla istisna maddesine giriyoruz. Ama bunun bedeli var: **komut yüzeyi menüde kalmalı** (§8.4).

### spec-v2'den bilinçli sapmalar

| Konu | spec-v2 | Bu belge | Gerekçe |
|---|---|---|---|
| Popover genişliği | 380 pt | **320 pt** | 288 pt içerik alanı, 24 kovalı grafik dahil tüm içeriği boşluksuz alıyor. §1'de ölçümle gösterildi |
| Yüzde göstergesi | 56 pt donut | **6 pt yatay bar** | macOS'ta sistem halka kontrolü yok; `NSProgressIndicator` bar var. §7.1 |
| Tazelik: yeşil nokta | her zaman görünür | **taze durumda nokta yok** | Kalıcı yeşil nokta dekorasyona dönüşür ve göz onu filtrelemeyi öğrenir. §7.4 |
| Alt komutlar | belirsiz | **popover içinde değil, dişli ikonundan açılan gerçek `NSMenu`'de** | HIG "menu, not a popover" kuralına kısmi uyum. §8.4 |

---

## 1. Boyut kararı

### 1.1 Karar

| Ölçü | Değer |
|---|---|
| **Popover içerik genişliği** | **320 pt** (sabit) |
| **Popover içerik yüksekliği** | **326 pt taban, 360 pt tavan** (içerik büyüdükçe intrinsic) |
| İç içerik alanı (yatay padding düşülmüş) | 288 pt |
| `NSPopover` çerçevesinin ekranda kapladığı alan | 346 × 352 pt (ölçülen 13 pt frame inset dahil) |

`NSPopover` içerik boyutuna 13 pt inset ekliyor: 280×180 pt içerik → 306×206 pt frame (canlı ölçüm, `shot3.swift`). Yani "320 pt" kullanıcının gördüğü kutu değil, bizim çizdiğimiz kutu.

### 1.2 Genişlik neden 320

Genişliği içerikten türetiyorum, rakipten kopyalamıyorum. En dar bileşen değil, en geniş bileşen belirler: **24 kovalı saat grafiği.**

24 kova, 8 pt bar ve 4 pt aralıkla:

```
24 × 8 + 23 × 4 = 192 + 92 = 284 pt
```

284 pt + 2 × 16 pt yatay padding = **316 pt**. 4 pt optik pay ile **320 pt**.

8 pt bar keyfi değil: `NSButton` checkbox'ın mini boyutu 12 pt, small 14 pt. 8 pt bar bunların altında kalan, ama 1 pt'lik hairline'ın üstünde duran, ekranda ayırt edilebilir en küçük dolu blok. 4 pt aralık ise 24 barın ayrı ayrı okunmasını sağlayan minimum.

Aynı 288 pt, ikinci en geniş bileşeni de alıyor: yüzde satırı.

```
"48%" (17 pt monospaced, ~40 pt) + 8 + "1,3×" (11 pt, ~28 pt) + esnek boşluk + sparkline 96 pt = 172 pt + boşluk
```

288 pt'de 116 pt esnek boşluk kalıyor. Türkçe metin İngilizceden uzun olduğu için bu pay gerekli (bkz. §1.4).

### 1.3 Rakiplerle karşılaştırma

| Uygulama | Yüzey | Genişlik × Yükseklik | İçerik yoğunluğu | Değerlendirme |
|---|---|---|---|---|
| Stats | `NSWindow` | 264 × 300 pt | modüler satır listesi, grafik yok | Bizim grafiklerimiz sığmaz |
| Usage4Claude | `NSPopover` | 280 × 240 pt | 1 donut + 5 kompakt satır | 24 kovalı grafik 280 pt'de kova başına 10 pt'ye düşer, okunabilirlik sınırında |
| **CodexBar** | `NSMenu` kartı | **310 pt taban**, içerik ölçülerek büyür | başlık + 2 kullanım penceresi + 6 pt barlar | **En yakın eşdeğer.** Aynı içerik sınıfı, ama saat grafiği yok. Bizim +10 pt'miz tam olarak o grafikten geliyor |
| CCSeva | `NSPopover` | 600 × 600 pt | 5 sekme, 70 pt donut'lar | Şişkin. Issue #17'de kullanıcı popover'ı taşınabilir pencereye çevirmek istiyor. Popover dashboard boyutuna çıkınca kullanıcı artık popover istemiyor |
| Maccy | `NSPanel` | 450 × 800 pt | uzun pano listesi | Farklı problem sınıfı, kıyas değil |
| **Claude Limit** | `NSPopover` | **320 × 326 pt** | başlık + 2 pencere + saat grafiği + tahmin satırı | CodexBar'dan 10 pt geniş, Usage4Claude'dan 40 pt geniş, CCSeva'nın kapladığı alanın **%29'u** |

CodexBar'ın 310 pt'si bir taban, tavan değil: `menuCardBaseWidth = 310`, `resolvedRenderedMenuWidth = max(ölçülenGenişlik, izlenenPencere, 310)`. Bizde 320 sabit, çünkü bizim içeriğimiz sağlayıcı sayısına göre değişmiyor: her zaman iki pencere.

### 1.4 Genişliğin sabit olmasının riski ve karşılığı

CodexBar issue #2959: 310 pt kart yerelleştirmede kırılıyor. Başlık ve reset metni tek `HStack`'i paylaşıyor, Rusça geri sayım cümleleri ve Çince mutlak tarihler kırpılıyor, çünkü `lineLimit`/`fixedSize` kısa İngilizceye göre ayarlanmış.

Bizim ana dilimiz Türkçe, yani bu risk MVP'de canlı. Karşılığı:

- Pencere başlığı satırı `ViewThatFits` ile önce `HStack` (etiket sol, reset sağ), sığmazsa `VStack` (reset alt satıra) dener.
- Reset metni asla `lineLimit(1)` + `truncationMode(.tail)` ile kırpılmaz; kırpma yerine satır düşürülür.
- Kırpma yalnızca hesap e-postası gibi kimlik dizelerinde serbest, sayısal bilgide asla.

### 1.5 Yükseklik dökümü

| Blok | Yükseklik | Not |
|---|---|---|
| Başlık bloğu | 53 pt | 10 üst + 16 başlık + 4 + 13 meta + 10 alt |
| Ayırıcı | 1 pt | |
| 5 saatlik bölüm | 74 pt | aşım notu yoksa |
| Ayırıcı | 1 pt | |
| Haftalık bölüm | 74 pt | |
| Ayırıcı | 1 pt | |
| En aktif saatler | 87 pt | 10 + 14 + 8 + 28 + 4 + 13 + 10 |
| Ayırıcı | 1 pt | |
| Fable satırı | 34 pt | 8 + 16 + 10 |
| **Toplam** | **326 pt** | |
| Her aşım notu | +17 pt | 4 boşluk + 13 satır. İkisi de görünürse tavan 360 pt |

Yükseklik `.fixedSize(horizontal: false, vertical: true)` ile içerikten gelir; `popover.contentSize` her açılışta ölçülür. Sabit yükseklik verilmez, aksi halde aşım notu görünmeyen durumda 34 pt boş alan kalır.

---

## 2. Menü çubuğu ögesi

### 2.1 Ölçü çerçevesi

| Ölçü | Değer | Kaynak |
|---|---|---|
| HIG'in beyan ettiği menü çubuğu yüksekliği | 24 pt | HIG "The menu bar > Menu bar extras" |
| `NSStatusBar.system.thickness` | 22.0 pt | canlı probe |
| `NSStatusBarButton.imageScaling` varsayılanı | `.scaleNone` (rawValue 2) | canlı probe |
| `variableLength` genişlik formülü | ikon genişliği + 16 pt | canlı probe (12→28, 16→32, 18→34, 22→38) |
| Sistem SF Symbol optik kutusu | ~15 pt | canlı probe |
| Status item buton fontu | 13.0 pt SF Pro | canlı probe |

**Kritik:** `imageScaling = .scaleNone` olduğu için **sistem görselinizi ölçeklemez.** 44 pt artwork verirseniz buton 44 pt olur ve macOS seçim vurgusunu diğer uygulamalardaki hap yerine şeridi taşan uzun blok olarak çizer (alt-tab `Menubar.swift:202-211` bunu birebir belgelemiş). Bu yüzden asset boyutu tasarım kararıdır, çalışma zamanı düzeltmesi değildir.

### 2.2 İkon: nasıl çizilecek

**Karar: SF Symbol değil, özel template görsel.** Gerekçe: hiçbir SF Symbol iki ayrı pencerenin dolulukları arasındaki ilişkiyi taşıyamaz. `gauge.with.dots.needle.bottom.50percent` tek bir değeri temsil eder, bizim iki değerimiz var ve kritik olan hangisi olduğu değişebiliyor.

| Ölçü | Değer | Kaynak |
|---|---|---|
| Tuval | 18 × 18 pt, `outputScale = 2` → 36 × 36 px | CodexBar `IconRenderer.swift:7-11` |
| Bar genişliği | 30 px = 15 pt, x = 3 px (ortalanmış) | CodexBar `IconRenderer.swift:134-135` |
| Üst bar (birincil pencere) | y = 19 px, h = 12 px → 6 pt | CodexBar `IconRenderer.swift:656-659` |
| Alt bar (ikincil pencere) | y = 5 px, h = 8 px → 4 pt | aynı |
| Stroke kalınlığı | 2 px = 1 pt, `inset = strokeWidthPx / 2` | CodexBar `IconRenderer.swift:163` |
| Track dolgu / stroke alfası | %28 / %44; eski veride %18 / %28 | CodexBar `IconRenderer.swift:129-131` |
| Köşe | kapsül (`cornerRadius = height / 2`) | |

Üst bar kalın (6 pt), alt bar ince (4 pt). Bu hiyerarşi kasıtlı: 18 pt'lik bir tuvalde iki eşit bar hangisinin önemli olduğunu söylemez.

**Piksel ızgarasına oturtma zorunlu.** Menü çubuğunda 1 pt'lik stroke yarım piksele denk gelirse bulanıklaşır. Tüm geometri piksel cinsinden yazılır ve pt'ye çevrilir:

```swift
private struct PixelGrid {
    let scale: CGFloat                                    // 2
    func pt(_ px: Int) -> CGFloat { CGFloat(px) / scale }
    func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
}
```

**`isTemplate = true`, istisnasız.** HIG birebir: *"Both interface icons and symbols use black and clear colors to define their shapes; the system can apply other colors to the black areas in each image so it looks good on both dark and light menu bars, and when your menu bar extra is selected."* Yani açık/koyu uyumu ve seçili durum tint'i **bizim işimiz değil.** Template'ten çıkıp renkli ikon çizmek üç şeyi birden bozar: koyu menü çubuğu, seçili durum, ve pasif ekranlarda AppKit'in uyguladığı soluklaştırma (CodexBar #2210).

**Eşik rengi ikona değil metne uygulanır.** Sebebi yukarıdaki template kuralı. Detay §2.5.

### 2.3 Metin formatı

Aktif pencere seçimi spec-v2 §3'ten geliyor: iki pencereden yüzdesi yüksek olan gösterilir.

| Durum | Gösterim | Not |
|---|---|---|
| Normal, 5 saatlik aktif | `[ikon]‌48%` | rozet yok |
| Normal, haftalık aktif | `[ikon]‌H 97%` | `H` rozeti, hangi pencereye bakıldığı belirsiz kalmaz |
| ≥ %85 | `[ikon]‌H 1s 12d` | yüzde yerine geri sayım. spec-v2 §3.3 |
| Veri eski (> 45 dk) | `[ikon]‌48%` soluk | `secondaryLabelColor`, ikon track alfası %18'e düşer |
| Veri hiç yok | `[ikon]‌--` | CCSeva'nın `"--"` deseni, tek makul boş durum |

**Token ayırıcı normal boşluk değil, `U+2009` THIN SPACE.** CodexBar `MenuBarLayoutRenderer.swift:344`. 13 pt'de normal boşluk menü çubuğunda gereğinden geniş duruyor ve ikonu metinden koparıyor.

**İkon `button.image`'a verilir, attributed title'ın içine gömülmez.** CodexBar'ın kod yorumu bunun sebebini birebir yazıyor: template görseller, AppKit'in pasif ekranlarda otomatik soluklaştırdığı **tek** menü çubuğu içeriğidir; attributed title attachment'ları önceden render edilmiş bitmap olduğu için sistemin active-state tinting'ini takip etmez.

```swift
button.image = iconImage                    // template, 18×18
button.imagePosition = title.length > 0 ? .imageLeft : .imageOnly
button.attributedTitle = renderedTitle
```

### 2.4 Monospaced rakam ve genişlik zıplamasının önlenmesi

**Font: `NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)`.**

13 pt seçimi: `NSFont.systemFontSize = 13.0` ve `NSFont.menuBarFont(ofSize: 0) = 13.0` (canlı probe). Menü çubuğundaki diğer tüm uygulama başlıkları bu boyutta. 11 pt'ye düşmek (CodexBar'ın "small" modu) komşularından küçük görünmek demektir.

**`monospacedDigitSystemFont` ≠ SF Mono.** Bu SF Pro'nun tabular figür varyantı; harfler proportional kalır, sadece rakamlar sabit genişlik alır. CCSeva'nın yaptığı gibi tüm arayüzü Fira Code'a çevirmek native değil, terminal estetiğidir.

Monospaced rakam **karakter sayısı değişimini çözmez.** `48%` → `100%` bir karakter daha uzun. Üç katmanlı çözüm:

1. **Genişlik rezervasyonu.** Mevcut moddaki en geniş olası dizeyi ölç, `statusItem.length`'i ona göre kilitle. Mod başına en geniş dizeler: `100%`, `H 100%`, `H 12s 59d`.
2. **Yalnızca değişince yaz.** `if !button.attributedTitle.isEqual(to: rendered) { button.attributedTitle = rendered }`. Aynı görünen başlığı yeniden atamak layout pass tetikler.
3. **Cache anahtarını saatten arındır.** Geri sayım dakikaya yuvarlanmış olarak cache anahtarına girer, ham saniye değil. Aksi halde her tick cache'i boşa çıkarır (CodexBar `MenuBarLayoutRenderer.swift:24-53`). LRU kapasitesi 64.

**`statusItem.length` formülü.** `NSStatusBarButton`'da content-inset API'si yoktur; padding'in tek mekanizması explicit length'tir (CodexBar `StatusItemController+MenuBarLayout.swift:285-293).

```swift
statusItem.length = ceil(iconWidth + thinSpaceWidth + reservedTextWidth) + 10
```

Hedef ayak izi: `H 100%` modunda 18 + 2 + ~48 + 10 = **~78 pt**, tavan **84 pt**.

Bu sayı boşuna değil. En yaygın kullanıcı şikayeti "çok küçük" değil, **"menü çubuğunda çok yer kaplıyor"** (CodexBar #2114: 313 × 30 px kaplıyor, kullanıcı 236 × 32 px kaplayan bir rakibi örnek gösteriyor). 14 inç MacBook'ta menü çubuğu alanı kıt ve sistem yer daralınca menü çubuğu extra'larını gizler. 84 pt tavanı bu şikayetin altında kalmak için var.

**Optik baseline:** `baselineOffset = -1` (tek satır). CodexBar'ın ölçtüğü optik ortalama düzeltmesi. İki satırlı düzen **desteklenmiyor**: 9 pt font ve 9.5 pt satır yüksekliği HIG'in 10 pt minimumunun altına düşer.

### 2.5 Eşik renkleri

| Bant | Kullanım | Metin rengi | Kaynak |
|---|---|---|---|
| Normal | 0 - 79 | `NSColor.labelColor` | HIG semantik renk |
| Uyarı | 80 - 94 | `NSColor.systemOrange` | spec-v2 §9 bildirim eşiği %80 |
| Kritik | 95 - 100 | `NSColor.systemRed` | spec-v2 §9 bildirim eşiği %95 |
| Eski veri | herhangi | `NSColor.secondaryLabelColor` | tazelik durumu renk bandını ezer |
| Status item vurgulu | herhangi | `NSColor.selectedMenuItemTextColor` | popover açıkken |

Geri sayıma geçiş eşiği (%85) uyarı bandının **içinde** duruyor. Bu bilinçli: %85'te renk zaten turuncu, geri sayım o rengin üstüne bilgi ekliyor, ayrı bir görsel durum açmıyor.

Menü çubuğu normal durumda **tamamen monokromdur.** Renk bir olay bildirir. `ai-usage-barometer` DESIGN.md'nin kontrast hedefi burada da geçerli: her renk kademesi açık menü çubuğu zeminine karşı en az ~3:1. `systemOrange` ve `systemRed` görünüme göre uyum sağladığı için bu hedefi kendileri tutar; hardcoded hex bunu tutmaz.

### 2.6 Status item yaşam döngüsü

```swift
statusItem.autosaveName = "ClaudeLimitStatusItem"      // pozisyon kalıcılığı
statusItem.behavior = .removalAllowed                   // kullanıcı sürükleyip atabilir
button.imageScaling = .scaleNone
button.sendAction(on: [.leftMouseDown, .rightMouseDown])
```

- `.removalAllowed` kullanıldığı için `isVisible` KVO ile izlenip tercih olarak kalıcılaştırılır. HIG: *"Let people, not your app, decide whether to put your menu bar extra in the menu bar."*
- `NSStatusBar.removeStatusItem` `preferredPosition`'ı siler. Kaldırmadan önce cache'lenip sonra geri yazılır (Ice `ControlItem.swift:123`, aynı fikir Stats'ta MIT lisansı altında `saveNSStatusItemPosition` olarak var).
- HIG: *"Avoid relying on the presence of menu bar extras."* Uygulama, menü çubuğu ögesi gizliyken de çalışır durumda kalır; bildirimler ögeye bağlı değildir.

---

## 3. Materyal ve zemin

### 3.1 Karar tablosu

| macOS | Popover zemini | Köşe |
|---|---|---|
| 26+ | **Özel arka plan yok.** Sistem chrome'u (`NSGlassView` / `NSGlassEffectView`) olduğu gibi bırakılır | sistem çizer |
| 15 ve öncesi | `NSVisualEffectView`, `material = .popover` (rawValue 6), `blendingMode = .behindWindow`, `state = .active` | sistem çizer |

**macOS 26'da kendi arka planımızı koymuyoruz.** "Adopting Liquid Glass" birebir: *"Audit the backgrounds of sheets and popovers... remove those custom background views."* Canlı layer ağacı bunu doğruluyor: `NSPopoverFrame > NSGlassView > _NSCoreHostingView<NSGlassEffectView>`. Sistem zaten Liquid Glass çiziyor; üstüne bir `NSVisualEffectView` koymak iki materyali üst üste bindirir.

**Materyal seçimi görünüme göre değil, semantiğe göre.** HIG birebir: *"Choose materials and effects based on semantic meaning and recommended usage. Avoid selecting a material or effect based on the apparent color it imparts to your interface, because system settings can change its appearance and behavior."*

Bu yüzden `.hudWindow` (rawValue 13) veya `.titlebar` (rawValue 3) kullanmıyoruz. Stats `.titlebar` kullanıyor ama Stats'ın yüzeyi `NSWindow`, bizimki `NSPopover`. Doğru semantik ad `.popover`.

`blendingMode = .behindWindow`: HIG macOS için iki mod tanımlıyor, behind-window ve within-window. Menü çubuğundan açılan yüzey masaüstünü ve arkadaki pencereleri görmeli.

### 3.2 Liquid Glass'ın sınırı

HIG Materials birebir: *"Don't use Liquid Glass in the content layer... Instead, use standard materials for elements in the content layer, such as app backgrounds."* ve *"Use Liquid Glass effects sparingly... Limit these effects to the most important functional elements in your app."*

Sonuç: **popover chrome'u Liquid Glass, içindeki hiçbir şey değil.** Limit kartlarına, grafiklere, satırlara `.glassEffect()` uygulanmaz. Bunlar içerik katmanıdır.

### 3.3 Köşe yarıçapları

| Yüzey | Yarıçap | Curve | Kaynak |
|---|---|---|---|
| Popover kapsayıcı | sistem çizer, dokunma | continuous | canlı ölçüm: `CASDFElementLayer cornerRadius = 20.0`, ancak SDF katmanı görünür gövdeye göre şişkin olduğu için birebir doğrulanamadı |
| Sistem menüsü kapsayıcısı | 12.0 pt | continuous | canlı ölçüm, kesin |
| `NSGlassEffectView` varsayılanı | 8.0 pt | continuous | canlı probe |
| **Bizim iç gruplarımız / hover kapsülü** | **7 pt** | **continuous** | menü seçim materyali `kCUIVariantContextMenuSelectionMaterial cornerRadius = 7.0`; Maccy da Tahoe'da 7 pt kullanıyor |
| İlerleme barı | 3 pt (= yükseklik / 2) | kapsül | |

**Yarıçap `.continuous` olacak, `.circular` değil.** Ölçülen tüm sistem katmanları `cornerCurve = continuous`. SwiftUI'da `RoundedRectangle(cornerRadius: 7, style: .continuous)`.

macOS 26'da iç içe şekiller için sabit yarıçap yerine concentric API tercih edilir. "Adopting Liquid Glass" birebir: *"Help maintain a sense of visual continuity in your interface by using rounded shapes that are concentric to their containers."*

```swift
if #available(macOS 26.0, *) {
    card.clipShape(.rect(corners: .concentric, isUniform: true))
} else {
    card.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
}
```

---

## 4. Tipografi ölçeği

### 4.1 Temel kurallar

- macOS varsayılan metin boyutu **13 pt**, mutlak minimum **10 pt** (HIG Typography).
- macOS **Dynamic Type desteklemez**. HIG birebir: *"macOS doesn't support Dynamic Type."* Boyutlar sabit yazılır.
- HIG: *"In general, avoid light font weights... prefer Regular, Medium, Semibold, or Bold font weights, and avoid Ultralight, Thin, and Light."* **Bu belgede hiçbir yerde Light veya Thin yok.**
- HIG'in macOS Headline stili **Bold**, semibold değil. Yaygın "13 pt semibold" alışkanlığı yanlış.

### 4.2 Ölçek

| Rol | Boyut / satır | Ağırlık | Tracking | HIG stili | Renk |
|---|---|---|---|---|---|
| Uygulama adı ("Claude Limit") | 13 / 16 | **Bold** | -0.08 pt | Headline | `labelColor` |
| Ana yüzde ("48%") | **17 / 22** | Regular, **monospaced digit** | -0.43 pt | Title 2 | eşik rengi |
| Hız çarpanı ("1,3×") | 11 / 14 | Regular, monospaced digit | +0.06 pt | Subheadline | `secondaryLabelColor` |
| Bölüm etiketi ("5 SAATLİK") | 10 / 13 | **Medium**, BÜYÜK HARF | **+0.12 pt** | Caption 2 | `tertiaryLabelColor` |
| Reset metni ("16:10'da sıfırlanır") | 10 / 13 | Regular | +0.12 pt | Footnote | `secondaryLabelColor` |
| Meta / tazelik ("2 dk önce") | 10 / 13 | Regular | +0.12 pt | Footnote | `tertiaryLabelColor` |
| Aşım notu ("Bu hızla 01:40'ta dolar") | 10 / 13 | Regular | +0.12 pt | Footnote | `systemOrange` |
| Fable satırı etiketi | 11 / 14 | Regular | +0.06 pt | Subheadline | `secondaryLabelColor` |
| "tahmini" rozeti | 10 / 13 | Medium | +0.12 pt | Caption 2 | `tertiaryLabelColor` |
| Saat ekseni ("00 06 12 18") | 10 / 13 | Regular, monospaced digit | +0.12 pt | Caption 1 | `tertiaryLabelColor` |
| Menü çubuğu başlığı | 13 | Regular, monospaced digit | 0 | `menuBarFont` | §2.5 |
| Dişli menüsü satırları | 13 | Regular | -0.08 pt | `menuFont(0)` | sistem çizer |

### 4.3 Tracking

macOS tracking boyuta göre değişir ve **12 pt'de sıfırdır**. HIG tablosu:

| Boyut | Tracking (1/1000 em) | pt karşılığı |
|---|---|---|
| 10 pt | +12 | +0.12 |
| 11 pt | +6 | +0.06 |
| 12 pt | 0 | 0.00 |
| 13 pt | -6 | -0.08 |
| 17 pt | -26 | -0.43 |

SwiftUI'da `.tracking(-0.08)`. Sabit bir letter-spacing değeri tüm boyutlara uygulamak yanlıştır. Bölüm etiketlerinde `+0.12` üstüne **ek olarak** büyük harf kern'i verilmez; Stats'ın `kern: 1.0` değeri bize fazla, çünkü Stats etiketi 10 pt semibold ve ortalanmış, bizimki sola yaslı.

### 4.4 Rakamlar

Değişen her sayı **monospaced digit** ile çizilir: yüzde, hız çarpanı, geri sayım, saat ekseni, Fable payı. Sabit metin (etiketler, "sıfırlanır") proportional kalır.

```swift
Text("48%").font(.system(size: 17, design: .default).monospacedDigit())
```

Bu `.monospaced()` değil `.monospacedDigit()`. Birincisi SF Mono'ya geçer ve native görünümü kaybeder.

---

## 5. Renk

### 5.1 Semantik renkler ve gerçek değerleri

macOS dinamik sistem renkleri **opaklık tabanlıdır, gri tonu değil.** Native görünümün en büyük tek belirleyicisi bu. Canlı sRGB ölçümü:

| Rol | Açık | Koyu |
|---|---|---|
| `labelColor` | siyah, alfa 0.847 | beyaz, alfa 0.847 |
| `secondaryLabelColor` | siyah, alfa 0.498 | beyaz, alfa 0.549 |
| `tertiaryLabelColor` | siyah, alfa 0.259 | beyaz, alfa 0.247 |
| `quaternaryLabelColor` | siyah, alfa 0.098 | beyaz, alfa 0.098 |
| `separatorColor` | siyah, alfa 0.098 | beyaz, alfa 0.098 |
| `windowBackgroundColor` | 255,255,255 | **30,30,30** |
| `controlAccentColor` | 0,122,255 (kullanıcı değiştirebilir) | aynı |

Buradan çıkan iki somut kural:

1. **Ayırıcı çizgi `#E5E5E5` değildir.** `separatorColor` = label renginin %9.8 opaklıklı hali. Açıkta siyah, koyuda beyaz. Sabit gri hex, koyu modda ya kaybolur ya çamurlaşır.
2. **Koyu mod zemini `#1E1E1E`, `#000000` değildir.** CCSeva'nın `Color.white.opacity(0.10)` track rengi tam da bu yüzden yanlış: açık modu hiç düşünmemiş.

HIG: *"Avoid using hard-coded color values or colors that don't adapt."* ve materyal üstündeki metin için: *"Regardless of the material you choose, use vibrant colors on top of it."* Pratikte bu, `labelColor` / `secondaryLabelColor` / `tertiaryLabelColor` demek. `#333` veya `rgba(0,0,0,0.6)` native değildir.

### 5.2 Eşik renkleri

| Bant | Kullanım % | Renk | Neden sistem rengi |
|---|---|---|---|
| Normal | 0 - 79 | Claude tint (§5.3) | ürün kimliği, uyarı değil |
| Uyarı | 80 - 94 | `NSColor.systemOrange` | görünüme ve artırılmış kontrast ayarına kendisi uyum sağlar |
| Kritik | 95 - 100 | `NSColor.systemRed` | aynı |

Eşikler **kullanılan** yüzde üzerinden, kalan üzerinden değil. spec-v2 §9'daki bildirim eşikleri (%80, %95) ile birebir aynı sayılar; kullanıcı bildirimi aldığı anda popover'da da rengin değiştiğini görür. İki farklı eşik seti tutmak (CodexBar kalan %10/%50 kullanıyor) kullanıcının kafasında iki ayrı model yaratır.

### 5.3 Claude tint

Normal bant için marka rengi kullanılır, sistem accent'i değil.

| Görünüm | Değer |
|---|---|
| Açık | `#CC7C5E` (rgb 204, 124, 94) |
| Koyu | `#E08D6B` (parlaklaştırılmış varyant) |

`#CC7C5E` CodexBar'ın Claude sağlayıcı tint'i. Koyu mod varyantı Usage4Claude'un `adjustedForDarkMode()` desenini izler: koyu zeminde aynı hex kontrastı düşürür. Hedef: materyal üstünde ≥ 3:1.

### 5.4 Accent rengi nerede kullanılır, nerede kullanılmaz

**Kullanılmaz:**
- İlerleme barı dolgusunda. `controlAccentColor` kullanıcı ayarıdır; kırmızı accent seçen kullanıcıda normal durumdaki bar kritik gibi görünür. Bu semantik çakışmadır.
- Grafiklerde, sparkline'da, saat barlarında.

**Kullanılır:**
- Dişli menüsündeki vurgulu satırda (zaten sistem çiziyor).
- Odaklanmış kontrolün focus ring'inde (sistem çiziyor).
- Ayarlar penceresindeki `Toggle` ve `Picker`'larda (sistem çiziyor).

Yani accent rengini biz hiçbir yere **elle** koymuyoruz; yalnızca sistem kontrollerinin onu kullanmasına izin veriyoruz.

### 5.5 Koyu mod

- Kontrast: HIG minimum **4.5:1**, küçük metinde hedef **7:1**. 10 pt Footnote metinlerimiz "küçük metin" sınıfında; `secondaryLabelColor` (alfa 0.549) koyu zeminde bunu tutar, `tertiaryLabelColor` (0.247) tutmaz. Bu yüzden 10 pt'de tertiary yalnızca **etiket** ve **eksen** için, hiçbir zaman değer için kullanılmaz.
- Desktop tinting: graphite accent seçildiğinde pencere arka planları masaüstü resminden renk alır. HIG bu yüzden özel bileşen arka planlarına biraz saydamlık koymayı öneriyor. Bizim özel arka planımız zaten yok (§3.1), tek istisna hover kapsülü ve o da materyal tabanlı (§8.1).
- Mod tespiti `NSApp.appearance` ile değil, **`button.effectiveAppearance`** ile yapılır. Menü çubuğu her zaman sistem temasını izler, uygulamanın kendi appearance override'ını değil (Usage4Claude `ColorScheme.swift:22-33`).

### 5.6 Renk körlüğü

Renk **tek başına** hiçbir bilgiyi taşımaz:

- Uyarı bandında bara **1 pt genişliğinde bir kesi işareti** eklenir, kritik bantta bu işaret 2 pt olur.
- Menü çubuğunda kritik durumda yüzde zaten geri sayıma dönüşür; yani biçim değişimi renk değişimine eşlik eder.
- İki pencere birbirinden renkle değil, **`H` rozetiyle** ve barın konumuyla ayrılır.

Usage4Claude'un şekil kodlaması (daire / altıgen / kare) bizde gereksiz: iki pencerede iki şekil, ayırt ediciliği rozet zaten sağlıyor ve iki farklı geometri 18 pt tuvalde okunmaz.

---

## 6. Boşluk ve ritim

### 6.1 Neden 8pt grid değil

**Apple macOS için 8pt grid kuralı yayınlamıyor.** HIG Layout sayfasının macOS bölümünün tamamı iki maddedir:

1. *"Avoid placing controls or critical information at the bottom of a window."*
2. *"Avoid displaying content within the camera housing at the top edge of the window."*

Standart kenar boşluğu, spacing skalası, grid yok. 8pt grid bir topluluk konvansiyonudur, Apple kuralı değil.

**Gerçek ritim sinyali menü metriklerindedir.** Canlı ölçülen `NSMenu` layout (5 item + 1 separator, toplam 141 pt):

| Ölçü | Değer |
|---|---|
| Üst / alt padding | 5 pt |
| Item satır yüksekliği | **24 pt** |
| Item metin leading inset | **14 pt** |
| Separator satırı | 11 pt (içinde 1 pt hairline, yatayda 16 pt inset) |
| Metin alanı yüksekliği | 16 pt (24 pt satırda 4 pt üst/alt inset) |

Ve standart kontrol yükseklikleri (canlı `sizeToFit` ölçümü):

| Kontrol | large | regular | small | mini |
|---|---|---|---|---|
| Push button | 28 | **24** | 20 | 16 |
| Popup button | 28 | **24** | 20 | 16 |
| Checkbox | 18 | 16 | 14 | 12 |
| Text field | - | **24** | - | - |
| Switch | 54 × 24 | 54 × 24 | 54 × 24 | 54 × 24 |

**Native bir macOS butonu 24 pt yüksekliğindedir.** Web'deki 40-48 px buton macOS'ta devasa durur. Bizim ritmimiz bu ailenin içinde kalır: 24 pt satır, 16 pt metin alanı, 4 pt inset.

### 6.2 Spacing tablosu

Tüm değerler tek bir `enum`'da toplanır (CodexBar `UsageMenuCardLayout` deseni), view'lara serpiştirilmez.

| Token | Değer | Nerede |
|---|---|---|
| `horizontalPadding` | **16 pt** | popover içeriğinin sol/sağ kenarı |
| `sectionTopPadding` | 10 pt | her bölümün üstü |
| `sectionBottomPadding` | 10 pt | her bölümün altı |
| `headerLineSpacing` | 4 pt | başlık ile meta satırı arası |
| `labelToValueSpacing` | 6 pt | bölüm etiketi ile değer satırı arası |
| `valueToBarSpacing` | 8 pt | değer satırı ile ilerleme barı arası |
| `barToNoteSpacing` | 4 pt | bar ile aşım notu arası |
| `chartToAxisSpacing` | 4 pt | saat barları ile eksen etiketleri arası |
| `inlineSpacing` | 8 pt | yüzde ile hız çarpanı arası |
| `separatorInset` | **16 pt** | ayırıcı hairline'ın yatay inset'i |
| `hoverCapsuleInset` | 5 pt | hover kapsülünün yatay inset'i |

`horizontalPadding = 16 pt` seçimi: CodexBar 20 pt kullanıyor, ama 20 pt bizim 24 kovalı grafiğimizi 280 pt'ye sıkıştırır ve kova başına 11.6 pt'ye düşürür. 16 pt, ölçülen `NSMenu` separator inset'i (16 pt) ile de birebir aynı, yani ayırıcılarımız sistem menüsüyle aynı ritimde duruyor.

### 6.3 Ayırıcı stili

```swift
Rectangle()
    .fill(Color(nsColor: .separatorColor))     // label renginin %9.8 alfası
    .frame(height: 1)
    .padding(.horizontal, 16)
```

- **1 pt hairline**, kutu çerçevesi değil, arka plan bloğu değil.
- 16 pt yatay inset. Canlı ölçüm: 136 pt genişliğinde menüde çizgi 104 pt, yani iki yanda 16'şar pt.
- Bölümler arasında **yalnızca ayırıcı** var. Ne kart arka planı, ne gölge, ne kenarlık. Web dashboard'ları bilgiyi kutulara koyar, macOS bilgiyi ayırıcılarla ayırır.

`Divider()` yerine explicit `Rectangle` kullanılıyor çünkü `Divider()`'ın kalınlığı ve rengi platform ve kapsayıcıya göre değişir; burada ikisi de sabit olmalı.

### 6.4 Dikey ritim özeti

```
┌────────────────── 320 pt ──────────────────┐
│ ↕10                                        │
│  Claude Limit                          ⚙︎  │  16 pt satır
│ ↕4                                         │
│  2 dk önce                                 │  13 pt satır
│ ↕10                                        │
├──── 1 pt hairline, 16 pt inset ────────────┤
│ ↕10                                        │
│  5 SAATLİK              16:10'da sıfırlanır│  14 pt
│ ↕6                                         │
│  48%  1,3×                    ▁▂▃▅▆▇┊╌╌╌   │  20 pt (sparkline 96×20, sağa yaslı)
│ ↕8                                         │
│  ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  6 pt bar, 288 pt genişlik
│ ↕10                                        │
├────────────────────────────────────────────┤
│  (haftalık bölüm, aynı yapı)               │
├────────────────────────────────────────────┤
│ ↕10                                        │
│  EN AKTİF SAATLER                          │  14 pt
│ ↕8                                         │
│  ▁▁▂▃▅▇█▇▅▃▂▁▁▁▂▃▄▅▄▃▂▁▁▁                  │  28 pt, 24 × (8 pt bar + 4 pt gap)
│ ↕4                                         │
│  00      06      12      18                │  13 pt
│ ↕10                                        │
├────────────────────────────────────────────┤
│ ↕8                                         │
│  Fable  tahmini                  %72  0,9× │  16 pt
│ ↕10                                        │
└────────────────────────────────────────────┘
```

---

## 7. Bileşenler

### 7.1 Yüzde göstergesi: halka değil, bar

**Karar: 6 pt yüksekliğinde, tam genişlikte, tam yuvarlatılmış yatay bar.**

Gerekçe, dört maddede:

1. **macOS'ta sistem halka kontrolü yoktur.** AppKit `NSProgressIndicator`'ı iki stille sunar: `.bar` ve `.spinning`. Determinate ilerleme için macOS idiomu bardır. Halka (Activity Rings) bir watchOS/iOS idiomudur. macOS'ta halka çizmek, platformun kendi dilinde olmayan bir form icat etmektir.
2. **Dikey maliyet.** 56 pt donut 56 pt yükseklik yer. 6 pt bar 6 pt. İki pencere için fark 100 pt, yani popover yüksekliğinin %30'u. "Çok büyük menubar yapma" kısıtı doğrudan bunu diskalifiye ediyor.
3. **Bar aynı zamanda bir zaman ekseni.** Yatay bar üzerinde "şu an olman gereken yer" (pace işareti) ve "bu hızla varacağın yer" (projeksiyon hayaleti) mekânsal olarak gösterilebilir. Halkada bu işaretler açı olarak okunur ve karşılaştırma zorlaşır.
4. **Rakip kanıtı.** Bar kullanan CodexBar ve Stats en native görünenler; 70 pt donut kullanan CCSeva ve 100 pt donut kullanan Usage4Claude en web/iOS görünenler. CCSeva'nın popover'ı bu yüzden 600 × 600 pt.

**Geometri:**

| Ölçü | Değer |
|---|---|
| Yükseklik | 6 pt |
| Genişlik | 288 pt (tam içerik genişliği) |
| Köşe | 3 pt (= yükseklik / 2), kapsül |
| Track | `tertiaryLabelColor` @ 0.22 alfa |
| Dolgu | eşik rengi (§5.2) |
| Pace işareti | 1 pt dikey kesi, `labelColor` @ 0.35 |
| Projeksiyon hayaleti | dolgu rengi @ 0.30, doldurulmuş kısmın devamı |

**Tek `Canvas` ile çizilir.** Bu bir estetik tercih değil, hata düzeltmesi: SwiftUI'ın `.compositingGroup` ve `.blendMode` modifier'ları macOS 26.x'te Metal/RenderBox shader derlemesini tetikliyor ve bu, menü çubuğu ikonunun kaybolmasına yol açıyor (CodexBar issue #805). Tek `Canvas` içeride Core Graphics kullanır ve bu modifier'lara ihtiyaç bırakmaz.

### 7.2 Sparkline ve kesikli projeksiyon

| Ölçü | Değer |
|---|---|
| Boyut | 96 × 20 pt, değer satırının sağına yaslı |
| Geçmiş çizgi | 1.25 pt, eşik rengi, `lineJoin = .round` |
| Geçmiş alan | eşik rengi @ 0.12, çizginin altı |
| Projeksiyon | 1 pt kesikli, dash pattern `[2, 2]`, aynı renk @ 0.55 |
| Aşım kesişimi | 3 pt dolu daire, `systemOrange` |
| Y ekseni | 0-100 sabit, otomatik ölçek yok |
| X ekseni | pencere başlangıcı → pencere sonu, sabit |

**Y ekseni neden sabit 0-100:** otomatik ölçekli sparkline, %2'lik bir dalgalanmayı %90'lık bir tırmanış gibi gösterir. Burada ölçek bilginin kendisi.

**Projeksiyon ayrı bir alan değil, eğrinin kesikli devamıdır.** spec-v2 §4 bunu doğru söylüyor, korunuyor. Kesikli çizgi "bu ölçülmüş değil, tahmin" demenin evrensel ve sessiz yoludur; ayrı bir "tahmin" kutusu açmak yer yer ve gürültü yaratır.

Çizgi kalınlığı 1.25 pt ve piksel ızgarasına snap edilir (`(v * 2).rounded() / 2`). 1 pt çizgi 2x ekranda yarım piksele denk gelirse gri lekeye dönüşür.

### 7.3 Saatlik bar grafiği

| Ölçü | Değer |
|---|---|
| Kova sayısı | 24 |
| Bar genişliği | 8 pt |
| Bar aralığı | 4 pt |
| Toplam genişlik | 284 pt (288 pt alanda 2 pt her yana pay) |
| Maksimum bar yüksekliği | 28 pt |
| Minimum bar yüksekliği | **2 pt** (boş saatler de görünür kalır) |
| Köşe | 1 pt, üst köşeler |
| Renk | `tertiaryLabelColor` |
| Mevcut saat | Claude tint (§5.3), tam opak |
| Eksen etiketleri | `00`, `06`, `12`, `18` (4 etiket, bar merkezlerine hizalı) |

**Minimum 2 pt neden var:** sıfır yükseklikli bar, "veri yok" ile "o saatte çalışılmamış"ı ayırt edilemez kılar. 2 pt'lik taban çizgisi 24 kovanın hepsinin var olduğunu söyler ve grafiğin şeklini bozmaz.

**Mevcut saat vurgusu** tek renkli vurgudur, kenarlık veya arka plan değil. Bu, "şu an neredeyim" sorusuna dokunmadan cevap verir.

Y ekseni etiketlenmez. Bu grafik mutlak değer değil, **dağılım** gösteriyor; sayı okumak isteyen kullanıcı hover ile tooltip alır (§8.1).

### 7.4 Tazelik göstergesi

spec-v2 §7'nin üç bandını koruyorum, ama görsel davranışını değiştiriyorum.

| Yaş | Gösterim | Nokta | Yüzdeler |
|---|---|---|---|
| < 10 dk | `2 dk önce` | **yok** | normal |
| 10 - 45 dk | `● 22 dk önce` | `systemYellow`, 5 pt | normal |
| > 45 dk | `● Eski veri · 1s 12d önce` | `systemGray`, 5 pt | `secondaryLabelColor`'a solar |
| veri yok | `Veri okunamadı` | `systemGray`, 5 pt | `--` |

**Taze durumda yeşil nokta yok.** Sebep: kullanıcının %95 gördüğü durum "taze" olacak. Kalıcı bir yeşil nokta dekorasyona dönüşür, göz onu filtrelemeyi öğrenir, ve gerçekten sarıya döndüğünde fark edilmez. Gösterge, **anomali olduğunda** görünür. spec-v2 §7'nin amacı ("gizlemeden söyle") bu şekilde daha iyi karşılanıyor.

Aynı mantık **servis durumu** için de geçerli: Anthropic servisi normalken hiçbir şey gösterilmez. Sorun varsa başlık satırının sağına `exclamationmark.triangle.fill` SF Symbol'ü (13 pt, `systemOrange`) gelir ve tıklanınca status sayfasını açar.

Nokta bir SF Symbol değil, 5 pt `Circle()`. `circle.fill` sembolü 5 pt'de optik olarak daha küçük çizilir ve metin baseline'ına oturmaz.

### 7.5 Fable satırı

```
Fable  tahmini                          %72  0,9×
```

- Tek satır, 16 pt yüksek, kendi bölümünde, ayırıcının altında.
- `tahmini` rozeti: 10 pt Medium, `tertiaryLabelColor`, arka plan **yok**. Kapsül arka planlı rozet web idiomudur; macOS'ta ikincil bilgi renk ve boyutla ayrılır, kutuyla değil.
- Bar yok. Bu değer tahmin, ve tahmine ölçülmüş değerlerle aynı görsel ağırlığı vermek yanlış bilgi verir. spec-v2 §4: *"Uydurma sayıyı kesin gibi göstermek yok."*
- Katman C açılıp gerçek değer geldiğinde `tahmini` rozeti kalkar ve satır kendi 6 pt barını kazanır. Bu, veri kalitesinin görsel ağırlığa dönüşmesidir.

---

## 8. Etkileşim

### 8.1 Hover

Native hover **satırın tamamını kaplayan düz gri dikdörtgen değildir.** Canlı ölçüm: menü seçim göstergesi `kCUIVariantContextMenuSelectionMaterial`, alt katmanları backdrop / tint / fill, `cornerRadius = 7.0`, yatayda inset'li.

Uygulanışı:

```swift
.background {
    if isHovering {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
    }
}
.padding(.horizontal, 5)
```

Hover **yalnızca tıklanabilir yüzeylerde** vardır:

| Yüzey | Hover | Aksiyon |
|---|---|---|
| Dişli ikonu | 7 pt kapsül | menü açar |
| Saatlik grafik barı | bar tam opak olur | tooltip: `14:00 · 312 istek` |
| Sparkline | değişmez | tooltip: kesişim saati |
| Limit bölümü (kart) | **yok** | tıklanabilir değil |
| Fable satırı | **yok** | tıklanabilir değil |

Tıklanabilir olmayan yüzeye hover vermek, kullanıcıya olmayan bir aksiyon vaat eder. Web dashboard'larında her kart hover'lanır; macOS'ta hover bir affordance'tır.

### 8.2 Tıklama

| Girdi | Davranış |
|---|---|
| Sol tık (status item) | popover aç / kapat |
| Sağ tık (status item) | doğrudan komut menüsünü aç (`NSMenu`) |
| Option + sol tık | veriyi zorla yenile, popover açmadan |
| Popover dışına tık | popover kapanır (`behavior = .transient`) |

`button.sendAction(on: [.leftMouseDown, .rightMouseDown])` şart; aksi halde sağ tık action'a ulaşmaz. Modifier `NSApp.currentEvent!.modifierFlags.intersection(.deviceIndependentFlagsMask)` üzerinden okunur.

Popover açıkken **status item butonu vurgulu kalır** (`button.isHighlighted = true`), kapanınca bırakılır. Bu native menü hissinin en kolay kaçırılan parçasıdır: vurgulanmayan bir status item, popover açıkken sistemden kopuk durur.

### 8.3 Açılış ve kapanış

**macOS 26+ tercih edilen yol: `NSStatusItemExpandedInterfaceDelegate`.**

macOS 26'da `NSStatusItem`'a `expandedInterfaceDelegate` ve `expandedInterfaceSession` eklendi. Dokümantasyon birebir: *"The delegate shows the expanded interface, such as an NSWindow positioned beneath the status item, in response to statusItem(\_:didBegin:), and dismisses the interface in response to statusItemDidEndExpandedInterfaceSession(\_:animated:)."*

Yani menü yerine özel bir yüzey açıyorsak, doğru yol elle `NSWindow` yönetmek değil, bu delegate. **Açılış/kapanış animasyonunu ve morph'u sistem yapar.** Elle yazılan bir fade/scale animasyonu Liquid Glass morph'unu taklit edemez.

**Dikkat:** `statusItem.menu` atanırsa delegate callback'leri gelmez. Sağ tık menüsü bu yüzden `menu` property'sine değil, action içinden `popUpMenu` ile açılır.

macOS 15 ve öncesinde `NSPopover`, `behavior = .transient`, `animates = true`, `show(relativeTo:of:preferredEdge: .minY)`.

Özel animasyon süresi tanımlanmaz. Maccy'nin 0.2 s'lik yeniden boyutlandırma animasyonu bizde gereksiz: popover boyutu açılışta sabitlenir, açıkken değişmez.

### 8.4 Komut yüzeyi: gerçek menü

HIG *"Display a menu, not a popover"* diyor. Veri görselleştirmesi için istisnaya giriyoruz, ama **komutlar için girmiyoruz.**

Başlık satırındaki dişli ikonu (`gearshape`, 13 pt, `secondaryLabelColor`) gerçek bir `NSMenu` açar:

| Satır | Kısayol |
|---|---|
| Şimdi Yenile | ⌘R |
| Ayarlar... | ⌘, |
| Claude'u Aç | |
| ayırıcı | |
| Claude Limit Hakkında | |
| Çık | ⌘Q |

Bu menü sistem çizer: 24 pt satır, 14 pt leading inset, 12 pt continuous köşe, 7 pt hover kapsülü, Liquid Glass zemin. Hiçbirini biz taklit etmiyoruz.

HIG Menus > Icons kuralı: *"Apply a uniform visual treatment across menu items in the same group. For visual consistency and balance, provide icons for all menu items in a group, or none of them."* Bu menüde **hiçbir satırda ikon yok**, çünkü "Şimdi Yenile" ve "Çık" için net sistem ikonları var ama "Claude Limit Hakkında" için yok. Karışık kullanmaktansa hiç kullanmıyoruz.

### 8.5 Klavye

| Tuş | Davranış |
|---|---|
| `Esc` | popover kapanır |
| `Tab` / `Shift+Tab` | odaklanabilir ögeler arasında gezinir (dişli ikonu) |
| `Space` / `Return` | odaklı ögeyi tetikler |
| `⌘R`, `⌘,`, `⌘Q` | dişli menüsündeki kısayollar, popover açıkken de çalışır |

Popover'da metin girişi yok, dolayısıyla `canBecomeKey` gerekmez ve popover odağı çalmaz. `NSPopover` varsayılan davranışı yeterlidir.

Global kısayol (popover'ı her yerden açma) MVP'de **yok.** Menü çubuğu ögesi zaten her zaman görünür ve global kısayol kaydı diğer uygulamalarla çakışma riski taşır.

### 8.6 Erişilebilirlik

```swift
button.setAccessibilityTitle("Claude Limit")
button.setAccessibilityValue("Haftalık limit yüzde 97, 1 saat 12 dakika sonra sıfırlanır")
```

- Status item değeri her zaman **tam cümle** olarak sunulur, `H 97%` gibi kısaltma olarak değil.
- Her bar ve sparkline `accessibilityLabel` + `accessibilityValue` taşır.
- Saatlik grafik tek bir erişilebilirlik ögesi olarak sunulur, 24 ayrı öge olarak değil; değeri "En yoğun saat 14:00" cümlesidir.
- "Reduce motion" açıkken sparkline'ın giriş animasyonu atlanır, değer doğrudan son haliyle çizilir.

---

## 9. SwiftUI kod iskeleti

### 9.1 Mimari kararı: `MenuBarExtra` değil, `NSStatusItem`

İncelenen 8 olgun repoda (`stats`, `Ice`, `alt-tab-macos`, `NetNewsWire`, `Maccy`, `CodexBar`, `eul`, `MonitorControl`) `menuBarExtraStyle` araması **sıfır sonuç** veriyor. `MenuBarExtra` yalnızca iki yerde geçiyor ve biri Maccy'nin "sahnesiz uygulama yaratılamıyor" sorununu aşmak için kurduğu boş kukla scene.

Karar: **AppKit `NSStatusItem` + `NSPopover`, içerik `NSHostingView` ile SwiftUI.** `MenuBarExtra(.window)` bize `statusItem.length` kontrolü, `attributedTitle`, `isHighlighted` yönetimi ve `expandedInterfaceDelegate` erişimi vermiyor; bunların hepsi §2 ve §8'deki kararların ön koşulu.

### 9.2 Layout sabitleri

```swift
// Sources/ClaudeLimit/UI/PopoverLayout.swift

enum PopoverLayout {
    static let width: CGFloat = 320
    static let horizontalPadding: CGFloat = 16
    static var contentWidth: CGFloat { width - horizontalPadding * 2 }   // 288

    static let sectionTopPadding: CGFloat = 10
    static let sectionBottomPadding: CGFloat = 10
    static let headerLineSpacing: CGFloat = 4
    static let labelToValueSpacing: CGFloat = 6
    static let valueToBarSpacing: CGFloat = 8
    static let barToNoteSpacing: CGFloat = 4
    static let inlineSpacing: CGFloat = 8

    static let separatorInset: CGFloat = 16
    static let hoverCapsuleInset: CGFloat = 5
    static let hoverCornerRadius: CGFloat = 7          // menü seçim materyali ölçümü

    static let progressBarHeight: CGFloat = 6
    static let sparklineSize = CGSize(width: 96, height: 20)

    // 24 × 8 + 23 × 4 = 284, contentWidth 288 içinde 2 pt her yana pay
    static let hourBarWidth: CGFloat = 8
    static let hourBarGap: CGFloat = 4
    static let hourChartHeight: CGFloat = 28
    static let hourBarMinHeight: CGFloat = 2
}

enum Typo {
    static let appName        = Font.system(size: 13, weight: .bold)
    static let primaryValue   = Font.system(size: 17).monospacedDigit()
    static let multiplier     = Font.system(size: 11).monospacedDigit()
    static let sectionLabel   = Font.system(size: 10, weight: .medium)
    static let footnote       = Font.system(size: 10)
    static let subheadline    = Font.system(size: 11)

    // macOS tracking tablosu: 17pt -0.43, 13pt -0.08, 11pt +0.06, 10pt +0.12
    static let tracking17: CGFloat = -0.43
    static let tracking13: CGFloat = -0.08
    static let tracking11: CGFloat = 0.06
    static let tracking10: CGFloat = 0.12
}

enum Palette {
    static let normal = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.878, green: 0.553, blue: 0.420, alpha: 1)   // #E08D6B
            : NSColor(srgbRed: 0.800, green: 0.486, blue: 0.369, alpha: 1)   // #CC7C5E
    })
    static let warning  = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)

    static func tint(forUsedPercent p: Double) -> Color {
        switch p {
        case ..<80:  return normal
        case ..<95:  return warning
        default:     return critical
        }
    }
}
```

### 9.3 Menü çubuğu kurulumu

```swift
// Sources/ClaudeLimit/MenuBar/StatusItemController.swift

import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var visibilityObserver: NSKeyValueObservation?
    private var lastRenderKey: MenuBarRenderKey?

    func install() {
        statusItem.autosaveName = "ClaudeLimitStatusItem"
        statusItem.behavior = .removalAllowed

        guard let button = statusItem.button else { return }
        // .scaleNone varsayılan: sistem görseli ölçeklemez, biz 18x18 veriyoruz
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.setAccessibilityTitle("Claude Limit")

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: PopoverLayout.width, height: 326)

        // HIG: kullanıcı ikonu menü çubuğundan atarsa tercihi kalıcılaştır
        visibilityObserver = statusItem.observe(\.isVisible, options: [.new]) { _, change in
            guard let visible = change.newValue else { return }
            Settings.shared.showInMenuBar = visible
        }
    }

    // MARK: - Menü çubuğu içeriği

    func render(_ snapshot: UsageSnapshot) {
        let key = MenuBarRenderKey(snapshot)          // geri sayım dakikaya yuvarlanmış
        guard key != lastRenderKey else { return }    // aynı görünen başlığı yeniden yazma
        lastRenderKey = key

        guard let button = statusItem.button else { return }

        button.image = MenuBarIconRenderer.image(for: snapshot)   // 18x18, isTemplate = true
        button.imagePosition = .imageLeft
        button.attributedTitle = Self.title(for: snapshot)
        button.setAccessibilityValue(snapshot.spokenSummary)

        // NSStatusBarButton'da content-inset API'si yok; padding'in tek mekanizması length
        let reserved = Self.reservedTextWidth(for: snapshot.mode)
        statusItem.length = ceil(18 + 2 + reserved) + 10
    }

    private static func title(for s: UsageSnapshot) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let color: NSColor
        if s.isStale                     { color = .secondaryLabelColor }
        else if s.usedPercent >= 95      { color = .systemRed }
        else if s.usedPercent >= 80      { color = .systemOrange }
        else                             { color = .labelColor }

        // ≥85: yüzde yerine geri sayım. Haftalık pencerede "H" rozeti.
        var text = s.usedPercent >= 85 ? s.countdownText : "\(Int(s.usedPercent))%"
        if s.window == .weekly { text = "H\u{2009}" + text }

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .baselineOffset: CGFloat(-1),        // optik ortalama
        ])
    }

    /// Moddaki en geniş olası dize. Genişlik zıplamasını monospaced rakam tek başına çözmez.
    private static func reservedTextWidth(for mode: MenuBarMode) -> CGFloat {
        let widest: String
        switch mode {
        case .fiveHourPercent: widest = "100%"
        case .weeklyPercent:   widest = "H\u{2009}100%"
        case .countdown:       widest = "H\u{2009}12s 59d"
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return (widest as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - Etkileşim

    @objc private func handleClick() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.type == .rightMouseDown {
            statusItem.menu = CommandMenu.build()      // gerçek NSMenu
            button.performClick(nil)
            statusItem.menu = nil                      // expandedInterface callback'lerini bloklamasın
            return
        }
        if flags.contains(.option) {
            UsageCoordinator.shared.forceRefresh()
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            button.isHighlighted = false
        } else {
            popover.contentViewController = NSHostingController(rootView: PopoverRootView())
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.isHighlighted = true                // native menü hissi için şart
        }
    }
}
```

### 9.4 Popover ana düzeni

```swift
// Sources/ClaudeLimit/UI/PopoverRootView.swift

struct PopoverRootView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderSection(freshness: store.freshness, service: store.serviceStatus)
            NativeSeparator()
            LimitSection(window: store.fiveHour, label: "5 SAATLİK")
            NativeSeparator()
            LimitSection(window: store.weekly, label: "HAFTALIK")
            NativeSeparator()
            ActiveHoursSection(buckets: store.hourlyBuckets)
            NativeSeparator()
            FableRow(estimate: store.fableEstimate)
        }
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)   // yükseklik içerikten
        // macOS 26: popover chrome'u zaten Liquid Glass. Özel arka plan YOK.
        // macOS 15 ve öncesi: NSViewRepresentable ile .popover materyali eklenir.
        .background(LegacyPopoverMaterial())
    }
}

struct NativeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))          // label renginin %9.8 alfası
            .frame(height: 1)
            .padding(.horizontal, PopoverLayout.separatorInset)
    }
}

struct LimitSection: View {
    let window: LimitWindow
    let label: String

    private var tint: Color { Palette.tint(forUsedPercent: window.usedPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Türkçe metin uzun: kırpma yerine satır düşür (CodexBar #2959)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PopoverLayout.inlineSpacing) {
                    sectionLabel
                    Spacer(minLength: 8)
                    resetText
                }
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel
                    resetText
                }
            }

            Spacer().frame(height: PopoverLayout.labelToValueSpacing)

            HStack(alignment: .firstTextBaseline, spacing: PopoverLayout.inlineSpacing) {
                Text("\(Int(window.usedPercent))%")
                    .font(Typo.primaryValue)
                    .tracking(Typo.tracking17)
                    .foregroundStyle(tint)

                Text(window.paceMultiplierText)                    // "1,3×"
                    .font(Typo.multiplier)
                    .tracking(Typo.tracking11)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                Spacer(minLength: 8)

                Sparkline(history: window.history,
                          projection: window.projection,
                          tint: tint)
                    .frame(width: PopoverLayout.sparklineSize.width,
                           height: PopoverLayout.sparklineSize.height)
            }

            Spacer().frame(height: PopoverLayout.valueToBarSpacing)

            UsageBar(used: window.usedPercent,
                     pace: window.pacePercent,
                     projected: window.projectedPercent,
                     tint: tint)
                .frame(height: PopoverLayout.progressBarHeight)

            if let overrun = window.overrunText {                  // "Bu hızla 01:40'ta dolar"
                Spacer().frame(height: PopoverLayout.barToNoteSpacing)
                Text(overrun)
                    .font(Typo.footnote)
                    .tracking(Typo.tracking10)
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .padding(.horizontal, PopoverLayout.horizontalPadding)
        .padding(.top, PopoverLayout.sectionTopPadding)
        .padding(.bottom, PopoverLayout.sectionBottomPadding)
        .opacity(window.isStale ? 0.55 : 1)                        // eski veri solar, silinmez
    }

    private var sectionLabel: some View {
        Text(label)
            .font(Typo.sectionLabel)
            .tracking(Typo.tracking10)
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
    }

    private var resetText: some View {
        Text(window.resetText)                                     // "16:10'da sıfırlanır"
            .font(Typo.footnote)
            .tracking(Typo.tracking10)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
    }
}
```

### 9.5 İlerleme barı: tek `Canvas`

```swift
// Sources/ClaudeLimit/UI/UsageBar.swift

struct UsageBar: View {
    let used: Double            // 0-100
    let pace: Double            // pencerede geçen süre yüzdesi
    let projected: Double       // bu hızla ulaşılacak yüzde
    let tint: Color

    var body: some View {
        // Tüm bar tek Canvas'ta. .compositingGroup / .blendMode macOS 26.x'te
        // Metal/RenderBox shader derlemesi tetikleyip status item ikonunu
        // kaybettiriyor (CodexBar #805). Canvas içeride Core Graphics kullanır.
        Canvas { ctx, size in
            let r = size.height / 2
            let cs = CGSize(width: r, height: r)
            let full = CGRect(origin: .zero, size: size)
            ctx.clip(to: Path(full))

            // track
            ctx.fill(Path { $0.addRoundedRect(in: full, cornerSize: cs) },
                     with: .color(Color(nsColor: .tertiaryLabelColor).opacity(0.22)))

            // projeksiyon hayaleti
            let projW = size.width * min(projected, 100) / 100
            if projW > 0 {
                ctx.fill(Path { $0.addRoundedRect(
                    in: CGRect(x: 0, y: 0, width: projW, height: size.height), cornerSize: cs) },
                    with: .color(tint.opacity(0.30)))
            }

            // gerçek dolgu
            let usedW = size.width * min(used, 100) / 100
            if usedW > 0 {
                ctx.fill(Path { $0.addRoundedRect(
                    in: CGRect(x: 0, y: 0, width: usedW, height: size.height), cornerSize: cs) },
                    with: .color(tint))
            }

            // pace kesisi: "şu an olman gereken yer"
            let paceX = (size.width * min(pace, 100) / 100).rounded()
            ctx.fill(Path(CGRect(x: paceX, y: 0, width: 1, height: size.height)),
                     with: .color(Color(nsColor: .labelColor).opacity(0.35)))
        }
        .accessibilityElement()
        .accessibilityLabel("Kullanım")
        .accessibilityValue("Yüzde \(Int(used)). Bu hızla yüzde \(Int(projected)).")
    }
}
```

### 9.6 Eski macOS için materyal

```swift
struct LegacyPopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            return NSView()                          // sistem Liquid Glass çiziyor, üstüne koyma
        }
        let v = NSVisualEffectView()
        v.material = .popover                        // semantik ada göre, görünüme göre değil
        v.blendingMode = .behindWindow               // masaüstünü görmeli
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

### 9.7 Info.plist

```xml
<key>LSUIElement</key><true/>
```

Dock'ta ve app switcher'da görünmez. Not: yalnızca menü çubuğunda yaşayan bir uygulama, kullanıcı ögeyi menü çubuğundan kaldırırsa sistem tarafından sonlandırılabilir; `.removalAllowed` + KVO ile tercih kalıcılaştırıldığı için yeniden başlatmada durum korunur.

---

## 10. Kaçınılacaklar

Bu uygulamayı web dashboard'una çevirecek somut hatalar. Her madde ya HIG'in bir cümlesine ya da ölçülmüş bir sistem değerine karşı geliyor.

### 10.1 Renk

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| `#333`, `rgba(0,0,0,.6)`, `#888` gibi sabit gri metin renkleri | HIG: *"Avoid using hard-coded color values or colors that don't adapt."* macOS renkleri opaklık tabanlı | `labelColor` / `secondaryLabelColor` / `tertiaryLabelColor` |
| Ayırıcı için `#E5E5E5` | `separatorColor` açıkta siyah %9.8, koyuda beyaz %9.8. Sabit gri koyu modda kaybolur | `Color(nsColor: .separatorColor)` |
| Koyu mod zemini `#000000` | Ölçülen `windowBackgroundColor` koyuda `30,30,30` | zemin çizme, materyale bırak |
| Tailwind paleti (`#10B981`, `#F59E0B`, `#EF4444`) | CCSeva'nın tam olarak yaptığı şey, en az native görünen uygulama | `systemGreen` / `systemOrange` / `systemRed` |
| Gradient dolgulu barlar ve halkalar | macOS'ta hiçbir sistem kontrolü gradient dolgu kullanmaz | düz semantik renk |
| İlerleme barına `controlAccentColor` | Kullanıcı ayarı; kırmızı accent seçende normal durum kritik gibi görünür | marka tint'i veya eşik rengi |
| `Color.white.opacity(0.10)` track | Açık modu yok sayar (CCSeva `Theme.swift:242`) | `tertiaryLabelColor.opacity(0.22)` |

### 10.2 Tipografi

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| 14 px / 16 px gövde metni | macOS varsayılanı 13 pt, minimum 10 pt | 13 pt gövde, 11 pt ikincil, 10 pt dipnot |
| SF Mono veya Fira Code ile tüm arayüz | Terminal estetiği. CCSeva'nın hatası | `.monospacedDigit()`, yalnızca rakamlarda |
| `.light` / `.thin` ağırlıklar | HIG: *"avoid Ultralight, Thin, and Light"* | Regular / Medium / Semibold / Bold |
| Headline'ı semibold yapmak | HIG macOS tablosu Headline'ı **Bold** diyor | 13 pt Bold |
| Tüm boyutlara aynı `letter-spacing` | macOS tracking boyuta göre değişir, 12 pt'de sıfırdır | 17→-0.43, 13→-0.08, 11→+0.06, 10→+0.12 |
| Bölüm başlıklarını BÜYÜK HARF yapmak (macOS 26 menülerinde) | macOS 26'da section header'lar title-style capitalization | popover'daki mikro etiketlerimizde büyük harf kalıyor (10 pt Caption 2, tracking +0.12), ama **menü** satırlarında asla |

### 10.3 Ölçü ve boşluk

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| 40-48 px yükseklikte butonlar | Native push button `regular` boyutta **24 pt** | 24 pt (regular), 28 pt (large) |
| 44 pt satır yüksekliği (iOS alışkanlığı) | Ölçülen `NSMenu` satırı **24 pt** | 24 pt satır, 16 pt metin alanı |
| Menü çubuğu ikonu için 44 pt artwork vermek | `imageScaling = .scaleNone`; buton 44 pt olur ve seçim vurgusu hap yerine taşan blok olur | 18 × 18 pt template |
| Popover'ı 500 pt+ genişletmek | HIG: *"Make a popover only big enough to display its contents."* CCSeva 600×600 → issue #17 "bunu pencere yapın" | 320 pt |
| Sabit popover yüksekliği | Aşım notu yokken 34 pt boş alan kalır | `fixedSize(horizontal: false, vertical: true)` |
| 8pt grid'i Apple kuralı sanmak | HIG Layout > macOS'ta yalnızca 2 madde var, grid yok | menü metriklerinden türetilen ritim (§6) |

### 10.4 Yüzey ve materyal

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| Popover içindeki her bloğa kart arka planı + gölge + kenarlık | macOS bilgiyi ayırıcıyla ayırır, kutuyla değil | 1 pt hairline, 16 pt inset |
| macOS 26'da popover'a kendi `NSVisualEffectView`'unu koymak | "Adopting Liquid Glass": *"remove those custom background views"* | arka plan koyma |
| İçerik ögelerine `.glassEffect()` | HIG: *"Don't use Liquid Glass in the content layer."* | içerikte standart materyal veya hiç |
| Materyali görünümüne göre seçmek (`.hudWindow` "koyu duruyor" diye) | HIG: semantiğe göre seç, görünüme göre değil | `.popover` |
| Köşe yarıçapını `.circular` bırakmak | Ölçülen tüm sistem katmanları `cornerCurve = continuous` | `.continuous`, macOS 26'da concentric API |
| Popover'a `×` kapat butonu koymak | Popover dışa tıklamayla kapanır. `×` bir web modal idiomudur | `behavior = .transient` |
| Popover içine sekme çubuğu koymak | CCSeva'nın 5 sekmesi popover'ı 600 pt'ye çıkardı | tek görünüm, derinlik gerekiyorsa ayrı pencere |

### 10.5 Etkileşim

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| Hover'da satırı kaplayan düz gri dikdörtgen | Native highlight `cornerRadius = 7`, yatayda inset'li, materyal tabanlı | 7 pt continuous kapsül, 5 pt inset |
| Tıklanabilir olmayan kartlara hover vermek | Olmayan bir aksiyon vaat eder | hover yalnızca affordance olduğunda |
| Komutları (Yenile / Ayarlar / Çık) popover içine buton olarak koymak | HIG: *"Display a menu, not a popover."* Komutlar için istisnaya girmiyoruz | gerçek `NSMenu` |
| Açılış/kapanış için elle fade + scale animasyonu | macOS 26'da sistem Liquid Glass morph'u yapıyor | `NSStatusItemExpandedInterfaceDelegate` veya `NSPopover` varsayılanı |
| Popover açıkken status item'ı vurgulamamak | Status item sistemden kopuk durur | `button.isHighlighted = true/false` |
| Sağ tık için `sendAction(on:)` atlamak | Sağ tık action'a hiç ulaşmaz | `[.leftMouseDown, .rightMouseDown]` |

### 10.6 Menü çubuğu

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| Renkli (non-template) ikon | Koyu menü çubuğu, seçili durum ve pasif ekran soluklaştırması bozulur | `isTemplate = true`, renk metinde |
| Emoji ile durum göstermek (⚠️ ⚡ ✅) | Menü çubuğunda ölçek ve hizalama kontrolü yok, template değil | SF Symbol veya template görsel |
| Metin genişliğini monospaced rakamla çözdüğünü sanmak | `48%` → `100%` bir karakter daha uzun | mod başına en geniş dizeyi ölç, `length`'i kilitle |
| Her tick'te `attributedTitle` yazmak | Aynı görünen başlık layout pass tetikler | değişince yaz, cache anahtarını saatten arındır |
| İkonu attributed title içine `NSTextAttachment` olarak gömmek | Bitmap olur, sistemin active-state tinting'ini takip etmez | `button.image` |
| İki satırlı (stacked) menü çubuğu düzeni | 9 pt font HIG'in 10 pt minimumunun altında | tek satır, 13 pt |
| İkona hep bir şey eklemek (rozet, karakter, animasyon) | CodexBar #1604: kullanıcılar "critter"ları kapatmak istedi | ikon sabit, bilgi barlarda |
| Menü çubuğu ögesinin varlığına güvenmek | HIG: *"Avoid relying on the presence of menu bar extras."* Sistem yer daralınca gizler | bildirimler ögeye bağlı olmasın |
| Menü çubuğu ayak izini ölçmemek | En yaygın şikayet bu (CodexBar #2114: 313 px) | ≤ 84 pt hedefi, her sürümde ölç |

### 10.7 Veri sunumu

| Hata | Neden yanlış | Doğrusu |
|---|---|---|
| Tahmini değeri ölçülmüş değerle aynı görsel ağırlıkta göstermek | Yanlış bilgi verir | Fable satırında bar yok, `tahmini` rozeti var |
| Eski veriyi taze gibi göstermek veya gizlemek | Rakiplerden ayrıştığımız yer bu | soldur, etiketle, silme |
| Otomatik ölçekli sparkline | %2'lik dalgalanmayı %90'lık tırmanış gibi gösterir | Y ekseni sabit 0-100 |
| Sıfır yükseklikli boş saat barları | "veri yok" ile "çalışılmamış" ayırt edilemez | minimum 2 pt taban |
| Projeksiyonu ayrı bir kutu/rozet olarak göstermek | Yer yer, gürültü yaratır | eğrinin kesikli devamı |
| `xu` gibi anlamı belirsiz alanı göstermek | spec-v2 §2: 3466 örneğin 321'inde var ve hep 100 | anlamı netleşene kadar gösterme |

---

## 11. Uygulama sırası

| Faz | Bu belgeden ne uygulanır | Doğrulama |
|---|---|---|
| 1 | §9.2 layout sabitleri, §5 renk paleti | Birim testi: eşik fonksiyonu 79/80/94/95 sınırlarında doğru renk döner |
| 2 | §2 menü çubuğu (ikon, attributed title, length kilidi) | Gerçek makinede ölç: `statusItem.length` ≤ 84 pt, `%0` → `%100` geçişinde genişlik değişmiyor |
| 3 | §9.4 popover düzeni, §7.1 bar, §6.3 ayırıcı | Ekran görüntüsü: açık ve koyu modda yan yana, kontrast ≥ 4.5:1 |
| 4 | §7.2 sparkline, §7.3 saat grafiği | 320 pt'de 24 kova kırpılmıyor, Türkçe reset metinleri kırpılmıyor |
| 5 | §8.3 `NSStatusItemExpandedInterfaceDelegate`, §8.4 komut menüsü | macOS 26'da morph animasyonu sistemden geliyor |

**Her fazda tek bir kabul kriteri:** ekran görüntüsünü sistem menüsünün yanına koy. İki yüzeyin satır ritmi, metin boyutu, ayırıcı tonu ve köşe eğrisi aynı aileye ait görünüyorsa geçer.
