import SwiftUI
import LimitCore

// MARK: - Limit kartı

private struct LimitWindowDetail: View {
    let window: WindowPresentation

    private var tint: Color { Palette.accent(for: window.accent, usedPercent: window.usedPercent) }
    private var track: Color { Palette.track(for: window.accent, usedPercent: window.usedPercent) }
    /// Eğri halkadan bir tık koyu, alan dolgusu düz ve çok soluk.
    private var lineTint: Color { Palette.line(for: window.accent, usedPercent: window.usedPercent) }
    private var areaFill: Color { Palette.soft(for: window.accent, usedPercent: window.usedPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Halka ile grafik sütunu YAN YANA ve AYNI BOYDA (görselde halka
            // 84,5 pt, grafik sütunu 80,4 pt). Zaman ekseni grafiğin altında
            // ama hâlâ o sütunun içinde: kartın dibine ayrı bir satır olarak
            // konursa kart 12 pt uzar ve halka satırın ortasında asılı kalır.
            HStack(alignment: .center, spacing: PopoverLayout.donutToChartGap) {
                DonutGauge(percent: window.usedPercent, tint: tint, track: track)
                    .frame(width: PopoverLayout.donutSize)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L.t("Kullanım geçmişi", "Usage history"))
                            .font(Typo.chartTitle)
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                            .fixedSize()

                        // Buraya `Spacer` EKLEME: sonsuz esnek bir Spacer ile
                        // `maxWidth: .infinity` yan yana durunca HStack artan
                        // yeri ARALARINDA paylaştırıyor ve rozete yalnız yarısı
                        // öneriliyor — `ViewThatFits` yer OLDUĞU HÂLDE kısa
                        // hâli seçiyor. Tek esnek çocuk kalınca öneri olduğu
                        // gibi geçiyor, `alignment` de hizayı koruyor.
                        if let multiplier = window.paceMultiplier {
                            ViewThatFits(in: .horizontal) {
                                RateBadge(multiplier: multiplier,
                                          label: L.t("kullanım hızı", "pace"))
                                RateBadge(multiplier: multiplier)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        } else if window.isFull {
                            Text(L.t("Doldu", "Full"))
                                .font(Typo.rateValue)
                                .foregroundStyle(Palette.criticalInk)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    HStack(alignment: .top, spacing: PopoverLayout.yAxisGap) {
                        YAxisScale()

                        AreaChart(
                            history: window.history,
                            projected: window.projectedPercent,
                            tint: lineTint,
                            areaFill: areaFill,
                            forecast: window.forecast,
                            willOverrun: window.willOverrun
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: PopoverLayout.chartHeight)
                        // Tahmini aşım grafiğin içinde, sağ altta: eğri o köşede
                        // hep yüksekte olduğu için alan boş kalıyor.
                        .overlay(alignment: .bottomTrailing) {
                            if let note = window.projectionNote {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(note.title)
                                    Text(note.value).monospacedDigit()
                                }
                                .font(Typo.axis)
                                .foregroundStyle(Palette.projection)
                                .padding(.trailing, 3)
                                .padding(.bottom, 2)
                                .help("\(note.title): \(note.value). \(note.basis)")
                            }
                        }
                    }
                    .padding(.top, PopoverLayout.chartTitleGap)

                    HStack(spacing: PopoverLayout.yAxisGap) {
                        Color.clear.frame(width: PopoverLayout.yAxisWidth, height: 1)
                        AxisLabels(labels: window.axisLabels)
                    }
                    .padding(.top, PopoverLayout.chartAxisGap)
                }
            }
        }
    }
}

/// İki limit tek kartta, üstte sekme çubuğuyla.
///
/// Sekmeler kartın İÇİNDE: dışarıda ayrı bir şerit olsaydı kartla arasında
/// boşluk kalır ve hangi kartı yönettiği zayıflardı. Seçili sekmenin adı
/// zaten kart başlığı olduğu için ayrıca başlık tekrarlanmıyor.
struct LimitContent: View {
    let current: WindowPresentation?
    let weekly: WindowPresentation?
    @Binding var showingWeekly: Bool

    private var shown: WindowPresentation? {
        showingWeekly ? (weekly ?? current) : (current ?? weekly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PopoverLayout.tabToBodyGap) {
            // Sekmeler kart BAŞLIĞININ yerinde, ayrı bir satırda değil.
            // Segmented control kendi yüksekliğiyle karta bir satır
            // ekler; seçili sekmenin adı zaten kart başlığı olduğu için
            // o satır ikinci kez yer kaplar. İki metin düğmesi başlıkla
            // aynı boyda, yani kart hiç büyümüyor.
            HStack(spacing: 8) {
                // Segment hapı: iki çip tek bir izin içinde. Alt çizgili
                // metin sekmesi seçili olanı gösterir ama İKİSİNİN
                // BİR SEÇİM olduğunu göstermez; ortak iz o bağı
                // kuruyor. 20 pt yükseklik, standart segmented control'ün
                // yaklaşık yarısı: kart bir satır uzamıyor.
                // Renkler ve puntolar görselden; ÖLÇÜ değil. Görseldeki hap
                // 126 × 23 pt; kullanıcı "çok yer kaplamasın" dediği için
                // yalnızca bu iki değer küçültüldü (çip yüksekliği 14 pt,
                // yatay iç boşluk 7 pt).
                HStack(spacing: 2) {
                    tab(L.t("Mevcut", "Current"), selected: !showingWeekly) { showingWeekly = false }
                    tab(L.t("Haftalık", "Weekly"), selected: showingWeekly) { showingWeekly = true }
                }
                // Çip 15, iz payı 1,5: hapın toplam boyu 18 pt'de
                // SABİT kalıyor ama seçili çip izi neredeyse dolduruyor.
                .padding(1.5)
                // Düz dolgu: pervaz ve gölge yok. Sekme bir DÜĞME değil,
                // hangi verinin gösterildiğini söyleyen bir etiket.
                .background(Capsule(style: .continuous).fill(Palette.tabTrack))

                Spacer(minLength: 6)

                if let shown, let absolute = shown.absoluteReset {
                    // Simge "Sıfırlanma:" kelimesinin yerini tutuyor: Fable
                    // ve Cüzdan kartlarındaki yenilenme satırıyla aynı
                    // kalıp, üç kart tek dil konuşuyor. Simge pencere
                    // türüne göre değişiyor, çünkü 5 saatlik pencerede
                    // değer bir SAAT ("19:40"), takvim simgesi onu tarih
                    // diye okutur.
                    MetaLine(symbol: shown.icon, text: absolute)
                        .help(shown.resetBadge)
                }
            }

            if let window = shown {
                // Sekme değişince kartın İÇİ tümüyle değişiyor (farklı
                // pencere, farklı eksen, farklı eğri). Kısa bir geçiş
                // "aynı kart, başka veri" diyor; anında takas ise iki ayrı
                // kart varmış hissi verir.
                LimitWindowDetail(window: window)
                    .id(window.kind)
                    .transition(.opacity)
            } else {
                // Veri YOKKEN kart boş kalmaz: ne olduğu, ne yapılması
                // gerektiği, hatanın kimde olduğu söylenir.
                // İlk açılış bu uygulamanın en kırılgan anı; kullanıcı
                // henüz hiçbir şey görmeden karar veriyor.
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("Henüz ölçüm yok", "No measurements yet"))
                        .font(Typo.body)
                        .foregroundStyle(Palette.secondaryText)
                    FootnoteText(text: L.t(
                        "Claude Desktop'ı kullanmaya başladığında ya da giriş yaptığında burada görünür.",
                        "This fills in once you start using Claude Desktop, or after you sign in."
                    ))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .transition(.opacity)
            }
        }
    }

    @State private var hoveringTab: String?
    /// `withAnimation` "Hareketi Azalt"ı kendisi denetlemiyor.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seçili çipin tabanı yarı saydam; saydamlık azaltılınca altına opak
    /// kart yüzeyi giriyor.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Seçili çipin zemini ve metni: gösterilen pencerenin kendi vurgusu.
    private var tabChip: Color { (shown?.accent ?? .fiveHour).chip }
    private var tabInk: Color { (shown?.accent ?? .fiveHour).ink }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.view) { action() }
        } label: {
            Text(title)
                .font(Typo.tab)
                // Seçili olmayan sekme SECONDARY, tertiary değil: açık temada
                // tertiary (189 grisi) macOS'un devre dışı metin değeriyle
                // birebir aynı ve "kapalı bir etiket" okunur; kullanıcı
                // ikinci veri setinin varlığını fark etmez.
                // Seçili çipin metni #802D18, seçili olmayan #5A5C69.
                .foregroundStyle(
                    selected ? tabInk
                        : (hoveringTab == title ? Palette.primaryText : Palette.secondaryText)
                )
                .padding(.horizontal, 8)
                .frame(height: 15)
                .background {
                    if selected {
                        // Kompozisyonun TEK OPAK ögesi. Her yüzey yarı
                        // saydamken göz bir çıpa arıyor; dolu çip hem o çıpa
                        // hem de "seçili olan bu" demenin en kısa yolu.
                        // Vurgu yıkaması OPAK TABANIN ÜSTÜNE biniyor, yoksa
                        // rengi camdan geçen masaüstü belirler.
                        ZStack {
                            if reduceTransparency {
                                Capsule(style: .continuous).fill(Palette.cardSurface)
                            }
                            Capsule(style: .continuous).fill(Palette.chipSolid)
                            Capsule(style: .continuous).fill(tabChip)
                        }
                        // `CardSurface`teki ile AYNI gerekçe: gruplanmamış bir
                        // yığında `.shadow` her çocuğa AYRI AYRI uygulanıyor,
                        // yani gölge iki kez çiziliyor ve üstteki %26'lık
                        // kapsül alttakinin gölgesini içeriden gösteriyor.
                        .compositingGroup()
                        // `glassShadow`un 0,43'ü %30 alfalı KART dolgusu için
                        // ÖNCEDEN ÇARPILMIŞ bir sayı. Çip %92'de olduğu için
                        // aynı belirteç burada ~0,40 çizerdi; çarpanı geri alıp
                        // kartla aynı ekran değerine (~0,13) oturtuyoruz.
                        .shadow(color: Palette.glassShadow.opacity(0.3), radius: 2, y: 0.5)
                    }
                }
                .motion(Motion.view, value: selected)
                .motion(Motion.view, value: hoveringTab == title)
        }
        .buttonStyle(.plain)
        .onHover { hoveringTab = $0 ? title : (hoveringTab == title ? nil : hoveringTab) }
    }
}
