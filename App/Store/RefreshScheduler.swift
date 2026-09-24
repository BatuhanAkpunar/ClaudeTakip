import AppKit
import Foundation

/// Zamanlayıcıların, uyanma gözlemcisinin ve dosya izleyicisinin sahibi.
///
/// Yalnızca NE ZAMAN çalışılacağını biliyor; NE yapılacağı store'dan gelen
/// kapanışlarda. Her kaynağın bir durdurma yolu var (`stop()`).
@MainActor
final class RefreshScheduler {
    private let watchedFile: URL
    private let onTick: @MainActor () -> Void
    private let onServer: @MainActor () -> Void
    private let onStatus: @MainActor () -> Void
    private let onCloud: @MainActor () -> Void
    private let onWake: @MainActor () -> Void
    private let onFileChange: @MainActor () -> Void

    private var timers: [Timer] = []
    private var wakeObserver: NSObjectProtocol?
    private var watcher: FileWatcher?

    init(
        watchedFile: URL,
        onTick: @escaping @MainActor () -> Void,
        onServer: @escaping @MainActor () -> Void,
        onStatus: @escaping @MainActor () -> Void,
        onCloud: @escaping @MainActor () -> Void,
        onWake: @escaping @MainActor () -> Void,
        onFileChange: @escaping @MainActor () -> Void
    ) {
        self.watchedFile = watchedFile
        self.onTick = onTick
        self.onServer = onServer
        self.onStatus = onStatus
        self.onCloud = onCloud
        self.onWake = onWake
        self.onFileChange = onFileChange
    }

    func start() {
        startWatching()

        // Geri sayımların akması ve verinin yaşlandığının görülmesi için.
        // Dosya değişmese bile kalan süre her dakika azalır.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Dosya sonradan oluşmuş olabilir: izleyici yoksa yeniden kur.
                if self.watcher == nil { self.startWatching() }
                self.onTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)

        // Sunucu okuması hem sayıları taze tutuyor hem de arşivi besliyor.
        // Sunucu dakikada bir: kullanıcı "ne kadar kullandım" sorusunun
        // cevabını gecikmeli görmemeli. Tek bir hafif GET, kota tüketmiyor.
        let server = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onServer() }
        }
        RunLoop.main.add(server, forMode: .common)
        timers.append(server)

        // Uykudan uyanma: zamanlayıcılar uyku boyunca durur ve uyanınca bir
        // sonraki tura kadar (dakikalar) ekranda bayat veri kalır. Sistem
        // bildirimi bunu kapatıyor ve geri çekilme sayacını da sıfırlıyor:
        // uyku sırasında biriken hatalar uyanınca anlamsız.
        //
        // Bildirim YALNIZCA NSWorkspace'in kendi merkezine gönderiliyor;
        // NotificationCenter.default'a bağlanan gözlemci hiç tetiklenmez.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onWake() }
        }

        // Servis durumu nadiren değişir, 15 dakikada bir yeterli.
        let status = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onStatus() }
        }
        RunLoop.main.add(status, forMode: .common)
        timers.append(status)

        // Bulut yedeği seyrek: her turda yalnızca birkaç yeni satır gidiyor
        // ve ücretsiz katmanın günlük istek bütçesini zorlamamak gerekiyor.
        let cloudTimer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onCloud() }
        }
        RunLoop.main.add(cloudTimer, forMode: .common)
        timers.append(cloudTimer)
    }

    func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func startWatching() {
        let candidate = FileWatcher(url: watchedFile) { [weak self] in
            Task { @MainActor in self?.onFileChange() }
        }
        // Kurulamadıysa referansı tutmuyoruz ki 30 saniyelik tur yeniden
        // denesin. Dosya Claude Desktop ilk çalıştığında oluşuyor.
        watcher = candidate.isWatching ? candidate : nil
    }
}
