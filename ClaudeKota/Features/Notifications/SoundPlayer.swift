import AVFoundation

@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?

    func playNotificationSound() {
        guard let url = Bundle.main.url(forResource: "notification", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Ses calamazsa sessiz devam et
        }
    }
}
