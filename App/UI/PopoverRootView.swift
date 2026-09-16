import SwiftUI
import AppKit
import LimitCore

struct PopoverRootView: View {
    let store: UsageStore

    /// Okunmuyor ama gerekli: dil ayarı değişince SwiftUI'nin bu ağacı
    /// yeniden çizmesini bu bağımlılık sağlıyor. `L.t` düz bir fonksiyon
    /// olduğu için tek başına görünümleri tetiklemiyor.
    @AppStorage(L.storageKey) private var language = L.Language.system.rawValue

    /// Ayarlar ayrı bir pencere değil, aynı popover'ın ikinci sayfası.
    /// Genişlik sabit olduğu için geçişte popover yatayda oynamıyor.
    @State private var showingSettings = false

    /// Hangi limit gösteriliyor. İki kartı alt alta dizmek popover'ı
    /// uzatıyordu ve ikisi aynı anda nadiren gerekiyor; sekme, yüksekliği
    /// yarıya indirip odağı tek pencereye veriyor.
    @State private var showingWeekly = false

    var body: some View {
        _ = language
        return Group {
            if showingSettings {
                SettingsPage(store: store) {
                    withAnimation(.easeInOut(duration: 0.2)) { showingSettings = false }
                }
                .transition(.opacity)
            } else {
                mainPage
                    .transition(.opacity)
            }
        }
        // Zemin OPAK: popover'ın kendi camı arkasındaki pencereleri geçiriyor
        // ve arkadaki içerik değişince ton oynuyordu. Kartların camı bu
        // zemini örnekliyor (pencere içi harmanlama), masaüstünü değil;
        // dolayısıyla popover arkasında ne olursa olsun aynı görünüyor.
        .background(GlassBackdrop())
    }

    private var mainPage: some View {
        VStack(spacing: PopoverLayout.cardSpacing) {
            HeaderBar(store: store) {
                withAnimation(.easeInOut(duration: 0.2)) { showingSettings = true }
            }

            if store.authState != .signedIn {
                MetricCard { SignInPrompt(store: store) }
                    .transition(.opacity)
            } else if let error = store.serverError {
                // Girişli kullanıcıda da hata görünmeli. Bu metin yalnızca giriş
                // kartında çiziliyordu ve o kart girişliyken hiç görünmüyordu:
                // Cloudflare engeli ya da ağ kesintisi sessizce yutuluyordu.
                ServerErrorBanner(message: error) { store.refreshServer() }
            }

            if let error = store.loadError {
                MetricCard { ErrorContent(message: error) }
            } else {
                LimitTabs(
                    current: store.fiveHour,
                    weekly: store.weekly,
                    showingWeekly: $showingWeekly
                )
                // Fable ve Cüzdan yan yana, ikisi de yarım genişlikte: aynı
                // türden iki "tek sayılık" kart, aynı satırda okunuyorlar.
                // İkisi de içeriğine göre boylanıyor, sabit yükseklik yok;
                // `alignment: .top` ile üst kenarları hizalı kalıyor.
                HStack(alignment: .top, spacing: PopoverLayout.cardSpacing) {
                    MetricCard(width: PopoverLayout.narrowCardWidth,
                               topPadding: PopoverLayout.dataCardTopPadding,
                               bottomPadding: PopoverLayout.dataCardBottomPadding) {
                        FableContent(usage: store.fableUsage, resetsAt: store.fableResetsAt)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)

                    MetricCard(width: PopoverLayout.wideCardWidth,
                               topPadding: PopoverLayout.dataCardTopPadding,
                               bottomPadding: PopoverLayout.dataCardBottomPadding) {
                        WalletContent(state: store.wallet)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Saat ısı şeridi TAM GENİŞLİKTE, en altta. Yarım kartta 24
                // saate 166 pt düşüyordu (hücre başına 6 pt) ve şerit dikey
                // çizilmek zorundaydı; tam genişlikte hücre başına 11 pt var,
                // yani günün akışı soldan sağa, okuma yönünde.
                MetricCard(topPadding: PopoverLayout.hoursCardTopPadding,
                           bottomPadding: PopoverLayout.hoursCardBottomPadding) {
                    ActiveHoursContent(profile: store.profile)
                }
            }
        }
        .padding(PopoverLayout.outerPadding)
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        // Bayatlama ANİ bir olay değil, eşiği geçen bir süreç: tek karede
        // sönmek "bir şey bozuldu" gibi okunuyordu.
        .opacity(store.freshness?.isStale == true ? 0.7 : 1)
        .motion(Motion.view, value: store.freshness?.isStale == true)
    }
}

// MARK: - Başlık

struct HeaderBar: View {
    let store: UsageStore
    let onSettings: () -> Void

    var body: some View {
        // Ölçülen konumlar: rozet x67, başlık x197, bulut x824, hap x908,
        // dişli x1157. Rozet→başlık arası 45 px → 13,2 pt; sağdaki üç öge
        // arası 28 px → 8,2 pt.
        HStack(spacing: 13.2) {
            AppMark()

            Text("Claude Limit")
                .font(Typo.title)
                .foregroundStyle(Palette.primaryText)

            Spacer(minLength: 6)

            // Sağdaki dört öge TEK bir denetim şeridi: hepsi aynı kart
            // yüzeyinde, aynı 22 pt boyunda, aynı kapsül dilinde. Önceden
            // ikisi çıplak simge, biri hap, biri renkli buluttu ve şerit
            // dört ayrı şeyden oluşuyor gibi duruyordu.
            HStack(spacing: 6) {
                ServiceStatusIcon(report: store.serviceStatus)

                // Simge ile yaş etiketi TEK düğme: ikisi aynı şeyi anlatıyor
                // ("veri ne kadar taze" / "şimdi tazele") ama iki ayrı öge
                // olarak dururken yaş etiketi tıklanamıyor, simge de neyi
                // yenilediğini söylemiyordu.
                RefreshPill(store: store)

                HeaderButton(systemName: "gearshape", help: L.t("Ayarlar", "Settings"), action: onSettings)

                HeaderButton(systemName: "power", help: L.t("Claude Limit'ten çık", "Quit Claude Limit")) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(height: PopoverLayout.headerHeight)
        // Görselde başlık şeridi kart kenarından 5 pt daha dışarıda başlıyor.
        .padding(.horizontal, PopoverLayout.headerInset - PopoverLayout.outerPadding + 7.75)
    }
}

/// status.claude.com durumu. Her şey yolundayken de gösterilir, çünkü bir
/// kesinti sırasında "acaba uygulama mı bozuk" sorusunun cevabı burada.
struct ServiceStatusIcon: View {
    let report: ServiceStatusReport?

    var body: some View {
        // Bulut da diğer düğmelerle aynı yuvarlak yüzeyde: renk durumu
        // söylüyor, biçim onu şeridin bir parçası yapıyor.
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: PopoverLayout.headerControlHeight,
                   height: PopoverLayout.headerControlHeight)
            .glassChip(Circle())
            .help(helpText)
            .onTapGesture {
                NSWorkspace.shared.open(URL(string: "https://status.claude.com")!)
            }
    }

    /// Okuma bu yaşı geçtiyse artık "şu an" hakkında bir şey söylemiyor.
    ///
    /// Kesinti sırasında status sayfasına da ulaşılamayabiliyor; o durumda son
    /// başarılı rapor ekranda kalıyor ve genelde "All Systems Operational"
    /// olduğu için tam da kesinti anında yanlış güvence veriyordu. İkonun var
    /// oluş sebebi "acaba sorun bende mi" sorusunu cevaplamak, dolayısıyla
    /// bayat bir cevabı taze gibi göstermek onu işlevsizden de kötü yapıyor.
    private static let staleAfter: TimeInterval = 45 * 60

    private var isStale: Bool {
        guard let report else { return false }
        return Date().timeIntervalSince(report.checkedAt) > Self.staleAfter
    }

    /// Simge HER ZAMAN bulut; durumu RENK söylüyor (yeşil / sarı / kırmızı).
    /// Şekil değiştirmek (üçgen, ünlem) simgeyi her kesintide başka bir şeye
    /// çeviriyordu; aynı yerde aynı nesnenin rengini izlemek daha hızlı okunuyor.
    private var symbol: String {
        // İçi dolu bulut = taze bilgi, içi boş = bilinmiyor ya da bayat.
        isStale || report == nil ? "cloud" : "cloud.fill"
    }

    private var tint: Color {
        if isStale { return Palette.tertiaryText }
        switch report?.status {
        case .operational: return Palette.green
        case .minor: return Palette.warning
        case .major, .critical: return Palette.critical
        default: return Palette.tertiaryText
        }
    }

    private var helpText: String {
        guard let report else { return L.t("Servis durumu okunamadı", "Could not read service status") }
        // Okumanın YAŞI her zaman görünüyor: üretilen `checkedAt` alanı
        // şimdiye kadar hiçbir yerde kullanılmıyordu.
        let age = Format.duration(Date().timeIntervalSince(report.checkedAt))
        if isStale {
            return L.t(
                "Servis durumu \(age) önce okundu, güncel olmayabilir · status.claude.com",
                "Service status read \(age) ago, may be out of date · status.claude.com"
            )
        }
        return "\(report.description) · \(age) · status.claude.com"
    }
}

struct HeaderButton: View {
    let systemName: String
    let help: String
    var spinning: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? Palette.primaryText : Palette.secondaryText)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .linear(duration: 0.2),
                    value: spinning
                )
                .frame(width: PopoverLayout.headerControlHeight,
                       height: PopoverLayout.headerControlHeight)
                .glassChip(Circle(), highlighted: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.view, value: hovering)
        .help(help)
    }
}

/// Uygulama işareti: mor zeminli yuvarlak köşeli rozet.
///
/// Çıplak simge başlık metninin yanında ikinci bir "ikon düğmesi" gibi
/// okunuyordu; sağdaki gerçek düğmelerle aynı ağırlıktaydı. Rozet onu bir
/// MARKA öğesine çeviriyor: tıklanabilir değil, uygulamanın kimliği.
struct AppMark: View {
    var body: some View {
        Image(systemName: "speedometer")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.violetInk)
            .frame(width: PopoverLayout.appMarkSize, height: PopoverLayout.appMarkSize)
            .glassChip(
                RoundedRectangle(cornerRadius: PopoverLayout.appMarkRadius, style: .continuous),
                tint: Palette.violet.opacity(0.30)
            )
    }
}

/// Yenile düğmesi + veri yaşı, tek hap.
struct RefreshPill: View {
    let store: UsageStore

    @State private var hovering = false

    private var dataDate: Date { store.freshness?.lastUpdate ?? store.lastRefreshedAt }

    private var ageTint: Color {
        switch store.freshness {
        case .aging: Color(nsColor: .systemYellow)
        case .stale: Color(nsColor: .systemGray)
        default: Palette.secondaryText
        }
    }

    var body: some View {
        Button { store.refreshAll() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.primaryText : Palette.secondaryText)
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    // Dönüş bittiğinde geri SARMIYOR: `.default` ile 360°'den
                    // 0°'ye dönmek çeyrek turu geri alıyordu ve "iptal edildi"
                    // gibi okunuyordu. Aynı süreli ileri geçiş turu tamamlıyor.
                    .animation(
                        store.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .linear(duration: 0.2),
                        value: store.isRefreshing
                    )

                Text(Format.age(dataDate))
                    .font(Typo.footnote)
                    .foregroundStyle(ageTint)
                    .fixedSize()
            }
            .padding(.horizontal, 9)
            .frame(height: PopoverLayout.headerControlHeight)
            .glassChip(Capsule(style: .continuous), highlighted: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.view, value: hovering)
        .help(helpText)
    }

    private var helpText: String {
        var text = L.t("Ekrandaki sayılar \(Format.age(dataDate)) önce alındı. Yenilemek için tıkla.",
                       "The numbers on screen were fetched \(Format.age(dataDate)) ago. Click to refresh.")
        if let freshness = store.freshness, freshness.isStale {
            text += L.t(" Kaynak eskidi: Claude Desktop kapalıyken dosya güncellenmiyor.",
                        " The source is stale: the file does not update while Claude Desktop is closed.")
        }
        return text
    }
}


// MARK: - Limit kartı

struct LimitCardContent: View {
    let window: WindowPresentation
    /// Sekmeli kullanımda başlık ve sıfırlanma bilgisi sekme satırına taşınıyor.
    var showsTitle: Bool = true
    var showsReset: Bool = true

    private var tint: Color { Palette.accent(for: window.accent, usedPercent: window.usedPercent) }
    private var track: Color { Palette.track(for: window.accent, usedPercent: window.usedPercent) }
    /// Eğri halkadan bir tık koyu, alan dolgusu düz ve çok soluk.
    private var lineTint: Color { Palette.line(for: window.accent, usedPercent: window.usedPercent) }
    private var areaFill: Color { window.usedPercent >= Palette.criticalThreshold
        ? Palette.critical.opacity(0.1) : window.accent.soft }

    var body: some View {
        VStack(alignment: .leading, spacing: 4.7) {
            if showsTitle {
                CardHeader(title: window.title) {
                    if let absolute = window.absoluteReset {
                        Text(L.t("Sıfırlanma: \(absolute)", "Resets: \(absolute)"))
                            .font(Typo.badge)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryText)
                            .help(window.resetBadge)
                    }
                }
            } else if showsReset, let absolute = window.absoluteReset {
                HStack {
                    Spacer(minLength: 0)
                    Text(L.t("Sıfırlanma: \(absolute)", "Resets: \(absolute)"))
                        .font(Typo.badge)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                        .help(window.resetBadge)
                }
            }

            // Halka ile grafik sütunu YAN YANA ve AYNI BOYDA (görselde halka
            // 84,5 pt, grafik sütunu 80,4 pt). Zaman ekseni grafiğin altında
            // ama hâlâ o sütunun içinde: kartın dibine ayrı bir satır olarak
            // konduğunda kart 12 pt uzuyordu ve halka satırın ortasında
            // asılı kalıyordu.
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

                        Spacer(minLength: 4)

                        if let multiplier = window.paceMultiplier {
                            RateBadge(multiplier: multiplier,
                                      label: L.t("kullanım hızı", "pace"))
                        } else if window.isFull {
                            Text(L.t("Doldu", "Full"))
                                .font(Typo.rateValue)
                                .foregroundStyle(Palette.critical)
                        }
                    }

                    HStack(alignment: .top, spacing: PopoverLayout.yAxisGap) {
                        YAxisScale(tickCount: window.axisLabels.count)

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
                                .font(axisFont(tickCount: window.axisLabels.count))
                                .foregroundStyle(note.isWarning ? Palette.projection : Palette.secondaryText)
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
struct LimitTabs: View {
    let current: WindowPresentation?
    let weekly: WindowPresentation?
    @Binding var showingWeekly: Bool

    private var shown: WindowPresentation? {
        showingWeekly ? (weekly ?? current) : (current ?? weekly)
    }

    var body: some View {
        MetricCard(topPadding: PopoverLayout.limitCardTopPadding,
                   bottomPadding: PopoverLayout.limitCardBottomPadding) {
            VStack(alignment: .leading, spacing: PopoverLayout.tabToBodyGap) {
                // Sekmeler kart BAŞLIĞININ yerinde, ayrı bir satırda değil.
                // Segmented control kendi yüksekliğiyle karta bir satır
                // ekliyordu; seçili sekmenin adı zaten kart başlığı olduğu için
                // o satır ikinci kez yer kaplıyordu. İki metin düğmesi başlıkla
                // aynı boyda, yani kart hiç büyümüyor.
                HStack(spacing: 8) {
                    // Segment hapı: iki çip tek bir izin içinde. Alt çizgili
                    // metin sekmesi seçili olanı gösteriyordu ama İKİSİNİN
                    // BİR SEÇİM olduğunu göstermiyordu; ortak iz o bağı
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
                    .padding(2)
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
                        // diye okutuyordu.
                        MetaLine(symbol: shown.icon, text: absolute)
                            .help(shown.resetBadge)
                    }
                }

                if let window = shown {
                    // Sekme değişince kartın İÇİ tümüyle değişiyor (farklı
                    // pencere, farklı eksen, farklı eğri). Kısa bir geçiş
                    // "aynı kart, başka veri" diyor; anında takas ise iki ayrı
                    // kart varmış hissi veriyordu.
                    LimitCardContent(window: window, showsTitle: false, showsReset: false)
                        .id(window.kind)
                        .transition(.opacity)
                } else {
                    // Veri YOKKEN kart bomboş kalıyordu: ne olduğu, ne
                    // yapılması gerektiği, hatanın kimde olduğu belirsizdi.
                    // İlk açılış bu uygulamanın en kırılgan anı; kullanıcı
                    // henüz hiçbir şey görmeden karar veriyor.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Henüz ölçüm yok", "No measurements yet"))
                            .font(Typo.body)
                            .foregroundStyle(Palette.secondaryText)
                        Text(L.t(
                            "Claude Desktop'ı kullanmaya başladığında ya da giriş yaptığında burada görünür.",
                            "This fills in once you start using Claude Desktop, or after you sign in."
                        ))
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .transition(.opacity)
                }
            }
        }
    }

    @State private var hoveringTab: String?

    /// Seçili çipin zemini ve metni: gösterilen pencerenin kendi vurgusu.
    private var tabChip: Color { (shown?.accent ?? .fiveHour).chip }
    private var tabInk: Color { (shown?.accent ?? .fiveHour).ink }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.view) { action() }
        } label: {
            Text(title)
                .font(Typo.tab)
                // Seçili olmayan sekme SECONDARY, tertiary değil: açık temada
                // tertiary (189 grisi) macOS'un devre dışı metin değeriyle
                // birebir aynıydı ve "kapalı bir etiket" okunuyordu; kullanıcı
                // ikinci veri setinin varlığını fark etmiyordu.
                // Seçili çipin metni #802D18, seçili olmayan #5A5C69.
                .foregroundStyle(
                    selected ? tabInk
                        : (hoveringTab == title ? Palette.primaryText : Palette.secondaryText)
                )
                .padding(.horizontal, 7)
                .frame(height: 14)
                .background(
                    Capsule(style: .continuous).fill(selected ? tabChip : .clear)
                )
                .motion(Motion.view, value: selected)
                .motion(Motion.view, value: hoveringTab == title)
        }
        .buttonStyle(.plain)
        .onHover { hoveringTab = $0 ? title : (hoveringTab == title ? nil : hoveringTab) }
    }
}

// MARK: - En aktif saatler

/// Saatlik alışkanlık kartı.
///
/// Kaynak token değil kota: kullanıcıyı durduran şey token sayısı değil,
/// harcanan kota. Ayrıca kota verisi herkeste var, token verisi yalnızca
/// Claude Code veya Desktop kullananlarda.
struct ActiveHoursContent: View {
    let profile: UsageProfile

    var body: some View {
        // Başlık tabanı y984, tepe etiketinin büyük harf üstü y996: aradaki
        // 12 px → 3,5 pt'yi iki satırın kendi kutu payları zaten dolduruyor,
        // ek boşluk yok.
        VStack(alignment: .leading, spacing: 0) {
            // Sağ üstteki "Az … Çok" ölçeği KALDIRILDI: skalanın yönü zaten
            // şeridin kendisinden okunuyor (soldan sağa günün akışı, koyulaşan
            // renk yoğunluk) ve başlığın karşısında ikinci bir okuma katmanı
            // açıyordu.
            CardHeader(title: L.t("En Aktif Saatler", "Most Active Hours"))

            // `isReliable` (en az 3 gün): tek bir günün verisiyle çizilen
            // harita desen değil gürültü gösteriyor, üstelik kesin bir dille.
            // Eşik `UsageProfile` içinde tanımlı ama şimdiye kadar hiçbir yerde
            // kullanılmıyordu; kart 1 günlük veride bile harita çiziyordu.
            if profile.isReliable {
                HourStream(hourly: profile.hourly, sampleDays: profile.hourSampleDays,
                           observedDays: profile.observedDays)
            } else {
                // Yeni kurulumda desen henüz yok. Boş bir şerit göstermek
                // yerine ne beklendiğini söylüyor.
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondaryText)
                    Text(L.t("Desen birikiyor", "Building a pattern"))
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: HourStream.height)
            }
        }
    }
}

/// Kart başlığı: ikon, ad ve varsa karşısındaki ikincil bilgi.
/// Üçü de aynı taban çizgisinde hizalanıyor.
struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // İkon yok: başlıklar sol üstte ikonsuz, daha sakin. Sağdaki alan
        // karta özel bir değer (yüzde, durum) taşıyabiliyor.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Typo.cardTitle)
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)

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

// MARK: - Fable

/// Kart altındaki meta bilgi: küçük simge + kısa değer.
///
/// "yenilenme 19 Eyl" ve "oto-yükleme açık" gibi düz cümleler kartın en alt
/// satırlarını gereksiz uzatıyor ve hepsi aynı gri tonda okunmadan geçiliyordu.
/// Simge ne olduğunu söylüyor, renk durumu söylüyor, metin yalnızca değeri
/// taşıyor: üç kanal, tek satır.
/// Durum rozeti: kısa bir hâlin adı, kendi zemininde.
///
/// Düz metin olarak yazıldığında ("Kapalı") kartın diğer ikincil satırlarıyla
/// aynı ağırlıktaydı ve bir DURUM olduğu okunmuyordu. Zemin onu satırdan
/// ayırıyor, renk hangi durum olduğunu söylüyor.
/// Görseldeki "etiket + rozet" satırı: solda ne olduğu, sağda hâli.
///
/// Etiket ile rozet arası 15 px → 4,4 pt; etiket "0,3×" ile aynı puntoda
/// (cap 18 px → 7,5 pt).
struct LabeledPill: View {
    let label: String
    /// Tam etiket sığmazsa kullanılan kısa hâl.
    let shortLabel: String
    let text: String
    var fill: Color = Palette.neutralPill
    var ink: Color = Palette.primaryText

    var body: some View {
        // Etiket KIRPILMIYOR: sığan hâl çiziliyor. "Tavan doldu" gibi uzun bir
        // durumda rozet 74 pt'ye çıkıyor ve tam etiketle birlikte satır
        // 151 pt oluyor; kartın sağ sütununa düşen yer 123 pt. O nadir durumda
        // etiket kısalıyor, anlamı ipucu taşıyor.
        ViewThatFits(in: .horizontal) {
            row(label)
            row(shortLabel)
        }
        .help(label)
    }

    private func row(_ text_: String) -> some View {
        HStack(spacing: 6) {
            Text(text_)
                .font(Typo.rateValue)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
            StatusPill(text: text, fill: fill, ink: ink)
        }
    }
}

struct StatusPill: View {
    let text: String
    var fill: Color = Palette.neutralPill
    var ink: Color = Palette.primaryText

    var body: some View {
        // Görselde "Açık" rozeti 32,7 × 14,9 pt; zemin #E2F1E5, metin #2A7955.
        // Nötr hâlde zemin #E8ECEF, metin #393E48.
        Text(text)
            .font(Typo.badge)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: PopoverLayout.statusPillHeight)
            // Düz dolgu: rozet bir durumun ADI, basılacak bir yüzey değil.
            .background(Capsule(style: .continuous).fill(fill))
    }
}

struct MetaLine: View {
    let symbol: String
    let text: String
    var tint: Color = Palette.secondaryText

    var body: some View {
        // Takvim simgesi 35×34 px → 10,2 pt; simge-metin arası 12 px → 3,5 pt.
        HStack(spacing: 3.5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .regular))
            Text(text)
                .font(Typo.footnote)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }
}

struct FableContent: View {
    /// Yüzde ve bu yüzdenin ÖLÇÜM mü TAHMİN mi olduğu.
    let usage: (percent: Double, isEstimate: Bool)?
    /// Fable kotasının sıfırlanma anı.
    let resetsAt: Date?

    private var percent: Double { usage?.percent ?? 0 }
    private var isEstimate: Bool { usage?.isEstimate ?? true }

    var body: some View {
        // Ölçülen taban çizgileri: başlık y682, "%4" y765, çubuk 788-811,
        // tarih y858. Aradaki paylar satır kutusu farkları çıkarılarak bulundu.
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Fable")

            // Esnek boşluk BURADA, kartın dibinde değil.
            //
            // İki kart aynı boyda; fazlalık eskiden çubuk ile tarih arasına
            // düşüyordu, dolayısıyla tarihin üstündeki boşluk kartın içeriğine
            // göre değişiyor ve altındakiyle eşit olmuyordu. Fazlalık başlıkla
            // gövde arasına alınınca tarihin iki yanındaki paylar SABİT ve
            // her iki kartta da aynı.
            Spacer(minLength: PopoverLayout.titleToHeroGap)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Tahminde "~": sayının ölçüm olmadığı tek karakterle
                // söyleniyor. Sunucudan gerçek kota gelince işaret düşüyor.
                if isEstimate {
                    Text("~")
                        .font(Typo.heroValue)
                        .foregroundStyle(Palette.secondaryText)
                }
                Text(L.t("%\(Int(percent.rounded()))", "\(Int(percent.rounded()))%"))
                    .font(Typo.heroValue)
                    .foregroundStyle(Palette.primaryText)
                Text(L.t("kullanıldı", "used"))
                    .font(Typo.heroLabel)
                    .foregroundStyle(Palette.secondaryText)
            }
            .motion(value: percent)

            SlimBar(percent: percent, tint: Palette.violet, track: Palette.violetTrack)
                .padding(.top, PopoverLayout.heroToBarGap)

            if let resetsAt {
                MetaLine(symbol: "calendar",
                         text: Format.resetSentence(resetsAt, includeTime: false))
                    .padding(.top, PopoverLayout.barToMetaGap)
                    .help(L.t("Yenilenme tarihi", "Renewal date"))
            }
        }
        .help(isEstimate
            ? L.t("Tahmini: sunucu Fable kotasını vermiyor, değer yerel token payından hesaplanıyor.",
                  "Estimated: the server is not reporting a Fable quota, so this is derived from the local token share.")
            : L.t("Fable modelinin haftalık kotası, doğrudan sunucudan.",
                  "Weekly quota for the Fable model, straight from the server."))
    }
}

/// Ekstra kullanım cüzdanı.
///
/// Yarım genişlikte, kadranın yanında. Kahraman sayı KALAN BAKİYE: para
/// bittiğinde iş durur, kullanıcının asıl sorusu odur. Yüzde en az işe yarayan
/// sayı olduğu için ikinci plana atıldı. Tüm durum mantığı `WalletPresentation`
/// içinde; burası yalnızca çiziyor.
struct WalletContent: View {
    let state: WalletState

    private var model: WalletPresentation { WalletPresentation.make(state) }

    var body: some View {
        let model = self.model
        // Görseldeki kurulum: solda kahraman sayı, SAĞDA iki "etiket + rozet"
        // satırı (Kredi Kullanımı · Oto-yenileme), altta yenilenme tarihi.
        // Kart bu yüzden Fable'dan geniş (190 pt / 148 pt).
        return VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: L.t("Cüzdan", "Wallet"))

            Spacer(minLength: PopoverLayout.titleToHeroGap)

            // Görseldeki kurulum: SOLDA kahraman sayı, SAĞDA iki "etiket +
            // rozet" satırı. Pencere 480 pt'ye çıktığı için ikisi yan yana
            // sığıyor; 360 pt'de sığmadığı için alt alta dizilmişlerdi.
            HStack(alignment: .center, spacing: 8) {
                if let hero = model.heroValue {
                    // Sayının yanında etiket YOK: "$9,18"in bakiye olduğunu
                    // kartın başlığı ve yanındaki "Kredi Kullanımı" satırı
                    // zaten söylüyordu, "bakiye" üçüncü kez tekrar ediyordu.
                    Text(hero)
                        .font(Typo.heroValue)
                        .foregroundStyle(Palette.primaryText)
                        .fixedSize()
                        .motion(value: hero)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: PopoverLayout.pillRowGap) {
                    LabeledPill(label: L.t("Kredi Kullanımı", "Extra usage"),
                                shortLabel: L.t("Kredi", "Usage"),
                                text: model.status,
                                fill: pillFill(model.statusTone),
                                ink: pillInk(model.statusTone))
                    if let autoReload = model.autoReload {
                        LabeledPill(
                            label: L.t("Oto Yenileme", "Auto-reload"),
                            shortLabel: L.t("Oto", "Auto"),
                            text: autoReload ? L.t("Açık", "On") : L.t("Kapalı", "Off"),
                            fill: autoReload ? Palette.greenSoft : Palette.neutralPill,
                            ink: autoReload ? Palette.greenInk : Palette.primaryText
                        )
                        .help(L.t("Otomatik bakiye yükleme", "Automatic balance top-up"))
                    }
                }
                .fixedSize()
            }

            if let fraction = model.barFraction {
                SlimBar(percent: fraction * 100, tint: color(model.barTone),
                        track: color(model.barTone).opacity(0.16))
                    .padding(.top, PopoverLayout.heroToBarGap)
            }

            if let detail = model.detail {
                Text(detail)
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .padding(.top, 4)
            }

            if let amounts = model.amounts {
                Text(amounts)
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            if let renewal = model.renewalDate {
                MetaLine(symbol: "calendar", text: renewal)
                    // +1 pt: Cüzdan'da tarihin üstündeki öge bir ROZET, yani
                    // yuvarlak uçlu bir kapsül. Kapsülün eğrilen alt kenarı
                    // Fable'daki düz çubuktan bir tık yukarıda okunuyor;
                    // ölçüldü, iki kartta da üst/alt payı 11 pt'ye getiriyor.
                    .padding(.top, PopoverLayout.barToMetaGap + 1)
                    .help(L.t("Bakiyenin yenilenme tarihi", "When the balance renews"))
            }
        }
        .help(model.help)
    }

    private func color(_ tone: WalletPresentation.Tone) -> Color {
        switch tone {
        case .calm: return Palette.blue
        case .warn: return Palette.warning
        case .danger: return Palette.critical
        case .muted: return Palette.secondaryText
        }
    }

    /// Rozet zemini: görselde "Açık" #E2F1E5, "Kapalı" #E8ECEF. Uyarı ve
    /// tehlike hâlleri görselde yok, sistem renginin soluk hâline düşüyorlar.
    private func pillFill(_ tone: WalletPresentation.Tone) -> Color {
        switch tone {
        case .calm: return Palette.greenSoft
        case .warn: return Palette.warning.opacity(0.16)
        case .danger: return Palette.critical.opacity(0.16)
        case .muted: return Palette.neutralPill
        }
    }

    /// Rozet metni: "Açık" #2A7955, "Kapalı" #393E48.
    private func pillInk(_ tone: WalletPresentation.Tone) -> Color {
        switch tone {
        case .calm: return Palette.greenInk
        case .warn: return Palette.warning
        case .danger: return Palette.critical
        case .muted: return Palette.primaryText
        }
    }
}


/// Girişsiz durum.
///
/// Uygulama girişsizken de çalışıyor: yerel dosyalardan okuduğu her şey
/// yerinde duruyor. Giriş yalnızca sunucu doğruluğunu ve cüzdanı açıyor.
/// Bu yüzden bu bir engel ekranı değil, bir davet kartı, ve popover'ın
/// geri kalanını hiç bozmuyor.
struct SignInPrompt: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: store.authState == .expired
                       ? L.t("Oturum düştü", "Session expired")
                       : L.t("Claude'a bağlan", "Connect to Claude"))

            Text(store.authState == .expired
                 ? L.t("Sayılar yerel dosyalardan gösteriliyor. Kesin değerler ve cüzdan için yeniden giriş yap.",
                       "Numbers are coming from local files. Sign in again for exact values and your wallet.")
                 : L.t("Her şey yerel dosyalardan okunuyor. Giriş yapınca yüzdeler sunucudan kesin gelir, cüzdan görünür.",
                       "Everything is read from local files. Sign in for exact server numbers and your wallet."))
                .font(Typo.footnote)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(store.authState == .expired
                       ? L.t("Yeniden giriş yap", "Sign in again")
                       : L.t("Giriş yap", "Sign in")) {
                    store.signIn()
                }
                .controlSize(.small)

                if let error = store.serverError {
                    Text(error)
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.warning)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Girişli kullanıcıya sunucu hatasını gösteren şerit.
///
/// Kart değil şerit: veri hâlâ yerelden geliyor ve gösteriliyor, bu bir engel
/// değil bir uyarı. Yeniden deneme düğmesi elin altında.
struct ServerErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(Typo.footnote)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button(L.t("Yeniden dene", "Try again"), action: onRetry)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.warning.opacity(0.12))
        )
        .padding(.horizontal, 4)
    }
}

struct ErrorContent: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.warning)
                .symbolRenderingMode(.hierarchical)
            Text(message)
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

