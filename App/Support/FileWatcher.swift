import Foundation

/// Tek bir dosyanın değişimini dinler.
///
/// Claude Desktop dosyayı yerine yazdığı için hem `.write` hem `.rename` ve
/// `.delete` izlenir, silinme durumunda izleme yeniden kurulur.
@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
    }

    /// İzleme gerçekten kuruldu mu. Dosya henüz yoksa (Claude Desktop hiç
    /// çalışmamışsa) `open` başarısız oluyor ve izleyici sessizce ölü kalıyordu:
    /// dosya sonradan oluştuğunda bir daha bağlanmıyordu.
    var isWatching: Bool { source != nil }

    private func start() {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            onChange()
            // Dosya yerine yazıldıysa eski tanımlayıcı ölü kalır, yeniden bağlan.
            if events.contains(.rename) || events.contains(.delete) {
                restart()
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    private func restart() {
        source?.cancel()
        source = nil
        descriptor = -1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
            self?.onChange()
        }
    }
}
