import SwiftUI
import LimitCore

/// Girişsiz durum.
///
/// Uygulama girişsizken de çalışıyor: yerel dosyalardan okuduğu her şey
/// yerinde duruyor. Giriş yalnızca sunucu doğruluğunu ve cüzdanı açıyor.
/// Bu yüzden bu bir engel ekranı değil, bir davet kartı, ve popover'ın
/// geri kalanını hiç bozmuyor.
struct SignInPrompt: View {
    let store: UsageStore

    private var isExpired: Bool { store.authState == .expired }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // `CardHeader` KULLANILMIYOR: o versal bir BÖLÜM ETİKETİ ve
            // buradaki metin bölüm adı değil, kullanıcıya söylenen bir cümle.
            // "OTURUM DÜŞTÜ" bağırmak olurdu.
            Text(isExpired
                 ? L.t("Oturum düştü", "Session expired")
                 : L.t("Claude'a bağlan", "Connect to Claude"))
                .font(Typo.cardTitle)
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            FootnoteText(text: isExpired
                 ? L.t("Sayılar yerel dosyalardan gösteriliyor. Kesin değerler ve cüzdan için yeniden giriş yap.",
                       "Numbers are coming from local files. Sign in again for exact values and your wallet.")
                 : L.t("Her şey yerel dosyalardan okunuyor. Giriş yapınca yüzdeler sunucudan kesin gelir, cüzdan görünür.",
                       "Everything is read from local files. Sign in for exact server numbers and your wallet."))

            HStack(spacing: 8) {
                Button(isExpired
                       ? L.t("Yeniden giriş yap", "Sign in again")
                       : L.t("Giriş yap", "Sign in")) {
                    store.signIn()
                }
                .controlSize(.small)

                if let error = store.serverError {
                    Text(error)
                        .font(Typo.footnote)
                        .foregroundStyle(Palette.warningInk)
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

    /// Kart yüzeyiyle aynı kural: saydamlık azaltılınca opak karşılık.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.warningInk)
            // Hata mesajı BİRİNCİL metin: okunması en gerekli cümle bu.
            FootnoteText(text: message, ink: Palette.primaryText)
            Spacer(minLength: 6)
            Button(L.t("Yeniden dene", "Try again"), action: onRetry)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Şerit KART SINIFINDAN bir yüzeyin üstünde. Saydam zeminde tek
        // başına %12'lik bir uyarı yıkaması neredeyse zeminin kendisi oluyor
        // ve metin doğrudan masaüstünün üstüne düşüyor. Kural: metin çıplak
        // zeminin üstünde durmaz.
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            ZStack {
                shape.fill(reduceTransparency ? Palette.cardSurface : Palette.glassTint)
                shape.fill(Palette.warning.opacity(0.12))
            }
        }
        // Şeride ayrı yatay pay EKLEME: kart sütunuyla aynı `outerPadding`
        // (8) içinde duruyor; 4 pt'lik bir pay onu kartların 4 pt İÇİNE alır.
    }
}

struct LoadErrorContent: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.warningInk)
                .symbolRenderingMode(.hierarchical)
            Text(message)
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
