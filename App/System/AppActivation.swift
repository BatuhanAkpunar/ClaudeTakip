import AppKit

/// Uygulamayı öne alan TEK yer.
///
/// Aksesuar uygulaması olduğumuz için bir pencere ya da popover göstermeden
/// önce öne alınıyoruz, yoksa pencere arkada kalıp görünmeyebiliyor.
/// `activate(ignoringOtherApps:)` kullanımdan kalkmış olsa da bu davranışı
/// veren çağrı o; kullanımdan kalkma uyarısı tek bir yerde kalsın diye burada.
@MainActor
enum AppActivation {
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
