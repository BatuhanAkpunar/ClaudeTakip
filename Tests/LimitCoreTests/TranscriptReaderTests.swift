import Testing
import Foundation
@testable import LimitCore

/// Claude Code transcript ayrıştırıcısının karakterizasyonu.
///
/// `parseDate` hız ve Sendable uyumu için `ISO8601DateFormatter` yerine elle
/// yazılmış; burada ikisinin aynı anı verdiği kilitleniyor. Tarihler `==` ile
/// değil 0,0005 sn toleransla karşılaştırılıyor: elle toplanan kesir ile
/// Foundation'ın milisaniye çözünürlüklü hesabı son bitte ayrışabiliyor.
@Suite("Transcript okuma")
struct TranscriptReaderTests {

    @Test("Elle ayrıştırma ISO8601DateFormatter ile aynı anı verir")
    func parseDateMatchesFormatter() throws {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let cases: [(text: String, formatter: ISO8601DateFormatter, epoch: TimeInterval)] = [
            ("1970-01-01T00:00:00Z", plain, 0),
            ("2024-02-29T23:59:59.954Z", fractional, 1_709_251_199.954),
            ("2026-08-21T08:47:59Z", plain, 1_787_302_079),
        ]
        for (text, formatter, epoch) in cases {
            let parsed = try #require(TranscriptReader.parseDate(text), "\(text)")
            let reference = try #require(formatter.date(from: text), "\(text)")
            #expect(abs(parsed.timeIntervalSince1970 - reference.timeIntervalSince1970) < 0.0005,
                    "\(text): \(parsed.timeIntervalSince1970) ≠ \(reference.timeIntervalSince1970)")
            #expect(abs(parsed.timeIntervalSince1970 - epoch) < 0.0005, "\(text)")
        }
        #expect(TranscriptReader.parseDate("garbage") == nil)
    }

    @Test("Aynı istek iki dosyada görünse de bir kez sayılır")
    func summarizeDedupes() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))

        // `message.id` farklı, `requestId` aynı: anahtar önce `requestId`.
        try Self.write(root, "a/x.jsonl", [
            Self.assistantLine(requestID: "req_ortak", messageID: "msg_a", stamp: stamp),
            Self.userLine(stamp: stamp),
        ])
        try Self.write(root, "b/y.jsonl", [
            Self.assistantLine(requestID: "req_ortak", messageID: "msg_b", stamp: stamp),
            Self.userLine(stamp: stamp),
        ])

        let summary = TranscriptReader(root: root).summarize()
        #expect(summary.eventCount == 1)
        #expect(summary.modelTokens == ["claude-opus-4-6": 115])
        #expect(summary.recentEvents.count == 1)
    }

    @Test("Geçmiş pencereye yetmiyorsa model payı hesaplanmaz")
    func shareTooShort() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        try Self.write(root, "a/x.jsonl", [
            Self.assistantLine(requestID: "req_tek", messageID: "msg_tek", stamp: stamp),
        ])

        let summary = TranscriptReader(root: root).summarize()
        let oldest = try #require(summary.recentEvents.first?.date)
        #expect(summary.share(matching: "claude-opus", since: oldest.addingTimeInterval(-1)) == nil)
        // Karşı örnek: pencere tam en eski olayda başlıyorsa pay hesaplanır.
        #expect(summary.share(matching: "claude-opus", since: oldest) == 1)
    }

    // MARK: - Yardımcılar

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ root: URL, _ relativePath: String, _ lines: [String]) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    /// Kullanım bloklu asistan satırı: 10 + 5 + 0 + 100 = 115 token.
    private static func assistantLine(requestID: String, messageID: String, stamp: String) -> String {
        #"{"type":"assistant","requestId":"\#(requestID)","timestamp":"\#(stamp)","message":{"id":"\#(messageID)","model":"claude-opus-4-6","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}}"#
    }

    /// Kullanım bloğu olmayan satır: sayıma girmemeli.
    private static func userLine(stamp: String) -> String {
        #"{"type":"user","timestamp":"\#(stamp)","message":{"role":"user","content":"bu satırda kullanım bilgisi yok"}}"#
    }
}
