import SwiftUI
import AppKit
import LimitCore

/// Popover içindeki ayarlar sayfası.
///
/// Ayrı pencere yerine burada olmasının sebebi: uygulamanın tüm arayüzü tek bir
/// popover ve dört anahtar için ikinci bir pencere açmak orantısız. Apple'ın
/// "ayarlar Cmd+, penceresinde" yönergesi ana penceresi olan uygulamalar için;
/// menü çubuğunda yaşayan bir araçta bağlam değiştirmek maliyet.
///
/// Genişlik ana sayfayla birebir aynı; geçiş yatay kaydırma değil yerinde
/// çapraz geçiş, yani hiçbir şey kaymıyor.
struct SettingsPage: View {
    let store: UsageStore
    let onBack: () -> Void

    @AppStorage(L.storageKey) private var language = L.Language.system.rawValue
    @AppStorage(SettingsKey.autoSessionEnabled) private var autoSession = SettingsKey.autoSessionDefault
    /// Hiç dokunulmadıysa açık; `CloudBackup.cloudEnabled` ile aynı varsayılan.
    @AppStorage(SettingsKey.cloudSyncEnabled) private var cloudSync = true
    @State private var eraseState: EraseState = .idle
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: PopoverLayout.cardSpacing) {
            header

            MetricCard { accountSection }

            // Tek grup. Ayarlar dört satır; başlıklı üç karta bölmek her
            // başlığa bir satır içerikten fazla yer verir.
            MetricCard {
                // Grup içi ritim 8: ayrımı çizgi değil MESAFE taşıyor.
                VStack(alignment: .leading, spacing: 8) {
                    languageRow
                    CompactToggle(L.t("Girişte başlat", "Launch at login"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            // Aşağıdaki geri yazma onChange'i yeniden
                            // tetikliyor. Anahtar zaten gerçeği yansıtıyorsa
                            // çıkılmalı: yoksa ters yönde bir kayıt isteği
                            // gidiyor ve hata mesajı nil ile eziliyordu.
                            guard enabled != LoginItem.isEnabled else { return }
                            loginError = LoginItem.set(enabled: enabled)
                            // Sistem reddederse anahtar gerçeği yansıtmalı.
                            launchAtLogin = LoginItem.isEnabled
                        }
                    // 5 saatlik pencereyi otomatik başlatma.
                    //
                    // Bu, uygulamanın kullanıcı hesabından İÇERİK ÜRETTİĞİ tek yer:
                    // claude.ai üzerinde bir sohbet açıp en ucuz modele "hi"
                    // gönderiyor, sonra sohbeti siliyor. Geri kalan her şey salt
                    // okuma. Varsayılan KAPALI: kullanıcı açıkça açmalı.
                    CompactToggle(
                        L.t("5 saatlik oturumu otomatik başlat",
                            "Start the 5-hour session automatically"),
                        isOn: $autoSession
                    )
                    CompactToggle(L.t("Bulut yedeği", "Cloud backup"), isOn: $cloudSync)
                    cloudEraseRow

                    // `Divider()` yerine açık dikdörtgen: Divider kalınlığını ve
                    // rengini sistemden alıyor ve yarı saydam kartın üstünde
                    // gereğinden koyu çiziliyor.
                    Rectangle()
                        .fill(Palette.separator)
                        .frame(height: 0.5)
                        .padding(.vertical, 1)
                    updatesRow

                    if let loginError {
                        FootnoteText(text: loginError, ink: Palette.warningInk)
                    }
                    // Oturum başlatma hatası: yalnızca bir şey ters gittiğinde
                    // görünüyor. Açıklama metni yok, anahtarın adı yeterli.
                    if case .failed(let message) = store.sessionStartState {
                        FootnoteText(text: message, ink: Palette.warningInk)
                    }
                    switch eraseState {
                    case .done:
                        FootnoteText(text: L.t("Buluttaki veri silindi, bulut yedeği kapatıldı.",
                                               "Cloud data erased, cloud backup turned off."))
                    case .failed:
                        FootnoteText(text: L.t("Buluttaki veri silinemedi. Bulut yedeği kapatıldı, daha sonra yeniden dene.",
                                               "Could not erase cloud data. Cloud backup is off; try again later."),
                                     ink: Palette.warningInk)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(PopoverLayout.outerPadding)
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Dil satırı. Anahtar satırlarıyla aynı ritimde: etiket solda, denetim
    /// sağda, aynı punto. Menü stili, çünkü üç seçenek bir segment şeridine
    /// sığdırıldığında "Türkçe" ile "İngilizce" 360 pt'de kırpılıyor.
    private var languageRow: some View {
        HStack {
            Text(L.t("Dil", "Language"))
                .font(Typo.body)
                .foregroundStyle(Palette.primaryText)

            Spacer(minLength: 8)

            Picker("", selection: $language) {
                ForEach(L.Language.allCases, id: \.rawValue) { option in
                    Text(L.t(option.label.tr, option.label.en)).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            // Pencere sunumu ve menü çubuğu metinleri `make()` anında
            // donduruluyor; yeniden kurulmazsa 30 saniyeye kadar eski dilde
            // kalıp hesaplanan metinlerle karışıyorlar.
            .onChange(of: language) { _, _ in store.refreshQuota() }
        }
    }

    enum EraseState: Equatable {
        case idle
        case confirming
        case erasing
        case done
        case failed
    }

    /// Buluttaki veriyi silme. Geri alınamadığı için iki adımlı: ilk basış
    /// onay ister. Uyarı penceresi değil satır içi onay, çünkü popover
    /// üstünde açılan pencere popover'ı kapatabiliyor.
    private var cloudEraseRow: some View {
        HStack {
            Text(L.t("Buluttaki veri", "Cloud data"))
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            switch eraseState {
            case .confirming:
                Button(L.t("Vazgeç", "Cancel")) { eraseState = .idle }
                    .controlSize(.small)
                Button(L.t("Evet, sil", "Yes, erase"), role: .destructive) { eraseCloud() }
                    .controlSize(.small)
            case .erasing:
                ProgressView()
                    .controlSize(.small)
            default:
                Button(L.t("Sil", "Erase")) { eraseState = .confirming }
                    .controlSize(.small)
            }
        }
    }

    private func eraseCloud() {
        eraseState = .erasing
        Task { @MainActor in
            eraseState = await store.eraseCloudData() ? .done : .failed
        }
    }

    /// Uygulama sürümü ve elle güncelleme denetimi.
    ///
    /// Güncellemeler saatte bir denetleniyor ve sessizce iniyor
    /// (`SUScheduledCheckInterval` 3600); bu düğme "hemen bak"
    /// için. Yayın derlemesinde her zaman var; DEBUG'da beslemesiz açılırsa
    /// güncelleyici yok, o yüzden düğme yalnızca gerçekten çalışacaksa çiziliyor.
    private var updatesRow: some View {
        HStack {
            Text(L.t("Sürüm \(Self.appVersion)", "Version \(Self.appVersion)"))
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            if store.updatesAvailable {
                Button(L.t("Güncellemeleri denetle", "Check for updates")) {
                    store.manualUpdateCheck?()
                }
                .controlSize(.small)
            } else {
                Text(L.t("otomatik", "automatic"))
                    .font(Typo.footnote)
                    // `tertiaryText` DEĞİL: o renk hiçbir zeminde 4,5:1'e
                    // ulaşmıyor ve kart saydamlaşınca daha da düşüyor.
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var header: some View {
        ZStack {
            // Başlık gerçekten ortada: geri düğmesi ZStack'te üstte durduğu için
            // başlığın hizasını kaydırmıyor, simetri hilesi gerekmiyor.
            Text(L.t("Ayarlar", "Settings"))
                .font(Typo.title)
                .foregroundStyle(Palette.primaryText)

            HStack {
                HeaderButton(systemName: "chevron.left", help: L.t("Geri", "Back"), action: onBack)
                Spacer()
            }
        }
        .padding(.horizontal, PopoverLayout.headerInset)
        .padding(.top, 2)
    }

    /// Hesap kartı.
    ///
    /// Künye ana popover'da değil burada: orada her açılışta yer kaplar ama
    /// nadiren okunan bir bilgi. Ayarlarda aradığın yerde ve tam hâliyle duruyor.
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: L.t("Hesap", "Account")) {
                // Durum ve eylem sağ üstte, yan yana: "Bağlı · Oturumu kapat".
                // Kartın dibindeki düğme, ilgili olduğu bilgiden uzaktı.
                HStack(spacing: 8) {
                    Text(store.authState == .signedIn ? L.t("Bağlı", "Connected") : L.t("Bağlı değil", "Not connected"))
                        .font(Typo.badge)
                        .foregroundStyle(store.authState == .signedIn ? Palette.green : Palette.secondaryText)
                    if store.authState == .signedOut {
                        Button(L.t("Giriş yap", "Sign in")) { store.signIn() }
                            .controlSize(.mini)
                    } else {
                        Button(L.t("Oturumu kapat", "Sign out")) { store.signOut() }
                            .controlSize(.mini)
                    }
                }
            }

            // Çerezin dolmasına az kaldıysa söyle (eşik: `SessionStore.expiryWarning`);
            // kullanıcı oturumun düştüğünü düşmeden önce öğrenir.
            if store.authState == .signedIn, let expires = store.sessionExpiresAt,
               let warning = SessionStore.expiryWarning(expiresAt: expires) {
                switch warning {
                case .expired:
                    FootnoteText(text: L.t("Oturum süresi doldu, yeniden giriş gerekecek.", "Session has expired, you will need to sign in again."),
                                 ink: Palette.warningInk)
                case .expiresWithin(let days):
                    FootnoteText(text: L.t("Oturum \(days) gün içinde dolacak, yeniden giriş gerekecek.", "Session expires within \(days) day(s), you will need to sign in again."),
                                 ink: Palette.warningInk)
                }
            }

            if let account = store.account {
                if let name = account.displayName ?? account.email {
                    InfoRow(L.t("Kullanıcı", "User"), name)
                }
                InfoRow(L.t("Plan", "Plan"), account.planLabel ?? L.t("Bilinmiyor", "Unknown"))
                if let renewal = account.inferredRenewal {
                    InfoRow(L.t("Yenilenme", "Renews"), Format.shortDate(renewal))
                }
            } else {
                Text(L.t("Hesap bilgisi okunamadı.", "Could not read account details."))
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }

            // Yenilenme tarihi türetilmiş bir sayı; kesin diye sunmak yanlış olur.
            if store.account?.inferredRenewal != nil {
                FootnoteText(text: L.t(
                    "Yenilenme tahmini: gerçek tarih yerel veride yok, aboneliğin başladığı günden hesaplanıyor.",
                    "Estimated renewal: the real date is not in the local data, so it is calculated from the day your subscription started."
                ))
            }
        }
    }
}

/// Popover genişliğinde çalışan yalın anahtar satırı.
///
/// `Form` burada kullanılamıyor: pencere için tasarlanmış ve 360 pt'de
/// etiketleri kırpıyor.
private struct CompactToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Typo.body)
                .foregroundStyle(Palette.primaryText)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(Typo.body)
                .foregroundStyle(Palette.primaryText)
        }
    }
}
