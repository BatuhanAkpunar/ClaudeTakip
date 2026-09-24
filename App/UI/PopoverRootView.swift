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
    /// uzatır ve ikisi aynı anda nadiren gerekiyor; sekme, yüksekliği
    /// yarıya indirip odağı tek pencereye veriyor.
    @State private var showingWeekly = false

    /// `withAnimation` `.motion(...)` değiştiricisinden geçmiyor; "Hareketi
    /// Azalt" burada ayrıca denetlenmeli.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        _ = language
        return Group {
            if showingSettings {
                SettingsPage(store: store) {
                    withAnimation(reduceMotion ? nil : Motion.layout) { showingSettings = false }
                }
                .transition(.opacity)
            } else {
                mainPage
                    .transition(.opacity)
            }
        }
        // Zemin bilinçli olarak YARI SAYDAM. Bedeli: kartların tonu arkadaki
        // içeriğe göre oynuyor; ama ÖLÇÜLÜ: kartın toplam geçirgenliği
        // (1 - glassTint) × (1 - popoverBase) ≈ 0,21, yani arkadakinin beşte
        // biri metnin altına ulaşıyor. Karşılığında `NSPopover`'ın kendi
        // bulanıklaştıran malzemesi görünür oluyor — saydamlık oradan geliyor,
        // biz bir katman eklemiyoruz.
        .background(GlassBackdrop())
    }

    private var mainPage: some View {
        let isStale = store.freshness?.isStale == true
        return VStack(spacing: PopoverLayout.cardSpacing) {
            HeaderBar(store: store) {
                withAnimation(reduceMotion ? nil : Motion.layout) { showingSettings = true }
            }

            if store.authState != .signedIn {
                MetricCard { SignInPrompt(store: store) }
                    .transition(.opacity)
            } else if let error = store.serverError {
                // Girişli kullanıcıda da hata görünmeli. Giriş kartı girişliyken
                // hiç görünmüyor; metin yalnızca orada olsaydı Cloudflare engeli
                // ya da ağ kesintisi sessizce yutulurdu.
                ServerErrorBanner(message: error) { store.refreshServer() }
            }

            if let error = store.loadError {
                MetricCard { LoadErrorContent(message: error) }
            } else {
                MetricCard(topPadding: PopoverLayout.limitCardTopPadding,
                           bottomPadding: PopoverLayout.limitCardBottomPadding) {
                    LimitContent(
                        current: store.fiveHour,
                        weekly: store.weekly,
                        showingWeekly: $showingWeekly
                    )
                }
                // Fable ve Cüzdan yan yana, ikisi de yarım genişlikte: aynı
                // türden iki "tek sayılık" kart, aynı satırda okunuyorlar.
                // İkisi de içeriğine göre boylanıyor, sabit yükseklik yok;
                // `alignment: .top` ile üst kenarları hizalı kalıyor.
                HStack(alignment: .top, spacing: PopoverLayout.cardSpacing) {
                    dataCard(width: PopoverLayout.narrowCardWidth) {
                        FableContent(usage: store.fableUsage, resetsAt: store.fableResetsAt)
                    }

                    dataCard(width: PopoverLayout.wideCardWidth) {
                        WalletContent(state: store.wallet)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // Saat ısı şeridi TAM GENİŞLİKTE, en altta. Yarım kartta 24
                // saate 166 pt düşer (hücre başına 6 pt) ve şerit dikey
                // çizilmek zorunda kalır; tam genişlikte hücre başına 11 pt var,
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
        // sönmek "bir şey bozuldu" gibi okunur.
        // Opaklık 0,88: bütün ağacı daha çok (ör. 0,7) soldurmak SAYDAM zeminde
        // kartın tonunu da zemine doğru çeker ve zaten sınırda olan ikincil
        // metin AA'nın altına iner. 0,88 aynı işareti veriyor, kontrastı bozmadan.
        .opacity(isStale ? 0.88 : 1)
        .motion(Motion.view, value: isStale)
    }

    /// Fable ve Cüzdan'ın ortak kart kabuğu: içerik üstte, kart satırın
    /// boyunu dolduruyor.
    private func dataCard(width: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
        MetricCard(width: width,
                   topPadding: PopoverLayout.dataCardTopPadding,
                   bottomPadding: PopoverLayout.dataCardBottomPadding) {
            content()
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }
}
