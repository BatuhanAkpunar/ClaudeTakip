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
    @AppStorage("autoSessionEnabled") private var autoSession = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: PopoverLayout.cardSpacing) {
            header

            MetricCard { accountSection }

            // Tek grup. Ayarlar dört satır; başlıklı üç karta bölmek her
            // başlığa bir satır içerikten fazla yer veriyordu.
            MetricCard {
                VStack(alignment: .leading, spacing: 10) {
                    languageRow
                    CompactToggle(L.t("Girişte başlat", "Launch at login"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            loginError = LoginItem.set(enabled: enabled)
                            // Sistem reddederse anahtar gerçeği yansıtmalı.
                            launchAtLogin = LoginItem.isEnabled
                        }
                    CompactToggle(
                        L.t("5 saatlik oturumu otomatik başlat",
                            "Start the 5-hour session automatically"),
                        isOn: $autoSession
                    )

                    Divider().opacity(0.5)
                    updatesRow

                    if let loginError {
                        Text(loginError)
                            .font(Typo.footnote)
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Oturum başlatma hatası: yalnızca bir şey ters gittiğinde
                    // görünüyor. Açıklama metni yok, anahtarın adı yeterli.
                    if case .failed(let message) = store.sessionStartState {
                        Text(message)
                            .font(Typo.footnote)
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(PopoverLayout.outerPadding)
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 5 saatlik pencereyi elle ya da otomatik başlatma.
    ///
    /// Bu, uygulamanın kullanıcı hesabından İÇERİK ÜRETTİĞİ tek yer: claude.ai
    /// üzerinde bir sohbet açıp en ucuz modele "hi" gönderiyor, sonra sohbeti
    /// siliyor. Geri kalan her şey salt okuma. Bu yüzden hem varsayılan kapalı
    /// hem de ne yaptığı ve riski açıkça yazılı; kullanıcı bilmeden açmasın.
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
        }
    }

    /// Uygulama sürümü ve elle güncelleme denetimi.
    ///
    /// Güncellemeler zaten günde bir kez sessizce iniyor; bu düğme "hemen bak"
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
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }

    static var appVersion: String {
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
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// Hesap kartı.
    ///
    /// Ana popover'ın altındaki tek satırlık künye buraya taşındı: orada her
    /// açılışta yer kaplıyordu ama nadiren okunan bir bilgiydi. Ayarlarda ise
    /// aradığın yerde ve tam hâliyle duruyor.
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

            // Çerezin dolmasına 3 günden az kaldıysa söyle: Claude Code'un
            // "login expires in 3 days" uyarısıyla aynı eşik. Eskiden tarih
            // hiç saklanmıyordu; kullanıcı oturumun düştüğünü ancak düştükten
            // sonra öğreniyordu.
            if store.authState == .signedIn, let expires = store.sessionExpiresAt {
                let left = expires.timeIntervalSinceNow
                if left < 3 * 24 * 3600 {
                    let days = max(0, Int((left / 86400).rounded(.up)))
                    Text(left <= 0
                         ? L.t("Oturum süresi doldu, yeniden giriş gerekecek.", "Session has expired, you will need to sign in again.")
                         : L.t("Oturum \(days) gün içinde dolacak, yeniden giriş gerekecek.", "Session expires within \(days) day(s), you will need to sign in again."))
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let account = store.account {
                if let name = account.displayName ?? account.email {
                    InfoRow(L.t("Kullanıcı", "User"), name)
                }
                InfoRow(L.t("Plan", "Plan"), account.planLabel)
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
                Text(L.t(
                    "Yenilenme tahmini: gerçek tarih yerel veride yok, aboneliğin başladığı günden hesaplanıyor.",
                    "Estimated renewal: the real date is not in the local data, so it is calculated from the day your subscription started."
                ))
                    .font(Typo.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Popover genişliğinde çalışan yalın anahtar satırı.
///
/// `Form` burada kullanılamıyor: pencere için tasarlanmış ve 360 pt'de
/// etiketleri kırpıyor.
struct CompactToggle: View {
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

struct InfoRow: View {
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
