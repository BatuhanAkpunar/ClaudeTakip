import ServiceManagement
import LimitCore

/// Girişte başlatma. `SMAppService` macOS 13'ten beri doğru API.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Başarılıysa nil, değilse kullanıcıya gösterilecek mesaj döner.
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            // İmzasız veya Applications dışından çalışan derlemelerde sistem
            // kaydı reddedebiliyor; sessizce yutmak yerine söylüyoruz.
            return L.t("Sistem isteği reddetti: \(error.localizedDescription)", "The system refused: \(error.localizedDescription)")
        }
    }
}
