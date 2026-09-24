import Testing
import Foundation
@testable import LimitCore

/// CloudSync ve ClaudeWebClient'ın ağa giden istek biçimini kilitler.
///
/// İki alt takım aynı statik StubURLProtocol durumunu paylaşıyor; bu yüzden
/// üst takım `.serialized`: paralel koşarlarsa işleyiciler birbirini ezer.
@Suite("Ağ istek biçimleri", .serialized)
struct NetworkShapeTests {
    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func object(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    @Suite("CloudSync")
    struct CloudSyncShape {
        let identity = CloudIdentity(deviceID: "d", secret: "s")

        func makeSync() -> CloudSync {
            CloudSync(endpoint: URL(string: "https://w.test")!, session: StubURLProtocol.session())
        }

        func samples(_ count: Int) -> [QuotaSample] {
            (0..<count).map {
                QuotaSample(date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + $0)),
                            org: "o", fiveHour: 10, sevenDay: 20, extraUsage: nil)
            }
        }

        @Test("1001 örnek 500+500+1 olarak üç POST isteğine bölünür")
        func yuklemeParcalanir() async throws {
            StubURLProtocol.reset { _ in (200, [:], NetworkShapeTests.json(["inserted": 1])) }
            let inserted = try await makeSync().upload(samples(1001), plan: nil, identity: identity)
            #expect(inserted == 3)

            let requests = StubURLProtocol.requests
            #expect(requests.count == 3)
            var sizes: [Int] = []
            for recorded in requests {
                #expect(recorded.request.httpMethod == "POST")
                #expect(recorded.request.url?.path == "/v1/samples")
                let root = try #require(NetworkShapeTests.object(recorded.body))
                #expect(Set(root.keys) == ["plan", "samples"])
                #expect(root["plan"] is NSNull)
                let rows = try #require(root["samples"] as? [[String: Any]])
                sizes.append(rows.count)
                for row in rows {
                    #expect(Set(row.keys) == ["t", "fiveHour", "sevenDay", "extra"])
                }
            }
            #expect(sizes == [500, 500, 1])
        }

        @Test("authorization başlığı Bearer deviceID.secret biçiminde")
        func yetkiBasligi() async throws {
            StubURLProtocol.reset { _ in (200, [:], NetworkShapeTests.json(["inserted": 1])) }
            try await makeSync().upload(samples(1), plan: "pro", identity: identity)
            let request = try #require(StubURLProtocol.requests.first?.request)
            #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer d.s")
        }

        @Test("Geçersiz hesap anahtarı x-account-key başlığı olarak gönderilmez")
        func gecersizHesapAnahtari() async throws {
            StubURLProtocol.reset { _ in (200, [:], NetworkShapeTests.json(["inserted": 1])) }
            try await makeSync().upload(samples(1), plan: nil, identity: identity, accountKey: "gecersiz")
            let request = try #require(StubURLProtocol.requests.first?.request)
            #expect(request.value(forHTTPHeaderField: "x-account-key") == nil)
        }

        @Test("Geçerli 64 onaltılık hesap anahtarı x-account-key başlığında gider")
        func gecerliHesapAnahtari() async throws {
            let key = String(repeating: "a1", count: 32)
            StubURLProtocol.reset { _ in (200, [:], NetworkShapeTests.json(["inserted": 1])) }
            try await makeSync().upload(samples(1), plan: nil, identity: identity, accountKey: key)
            let request = try #require(StubURLProtocol.requests.first?.request)
            #expect(request.value(forHTTPHeaderField: "x-account-key") == key)
        }

        @Test("İndirme hasMore ile ikinci sayfayı ister, her istekte since ve limit=10000 var")
        func indirmeSayfalanir() async throws {
            StubURLProtocol.reset { request in
                let since = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "since" })?.value
                if since == "1000000" {
                    return (200, [:], NetworkShapeTests.json([
                        "samples": [["t": 1_500_000, "fiveHour": 1, "sevenDay": 2]],
                        "hasMore": true,
                        "nextSince": 2_000_000,
                    ]))
                }
                return (200, [:], NetworkShapeTests.json(["samples": [] as [Any], "hasMore": false]))
            }
            let result = try await makeSync().download(
                since: Date(timeIntervalSince1970: 1000), identity: identity
            )
            #expect(result.count == 1)

            let requests = StubURLProtocol.requests
            #expect(requests.count == 2)
            var sinceValues: [String?] = []
            for recorded in requests {
                #expect(recorded.request.httpMethod == "GET")
                let items = URLComponents(url: recorded.request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems ?? []
                sinceValues.append(items.first(where: { $0.name == "since" })?.value)
                #expect(items.first(where: { $0.name == "limit" })?.value == "10000")
            }
            #expect(sinceValues == ["1000000", "2000000"])
        }

        @Test("İlerlemeyen nextSince tek istekte durur")
        func ilerlemeyenSayfa() async throws {
            StubURLProtocol.reset { _ in
                (200, [:], NetworkShapeTests.json([
                    "samples": [] as [Any], "hasMore": true, "nextSince": 1_000_000,
                ]))
            }
            _ = try await makeSync().download(
                since: Date(timeIntervalSince1970: 1000), identity: identity
            )
            #expect(StubURLProtocol.requests.count == 1)
        }

        @Test("401 yanıtı notRegistered hatasına dönüşür")
        func yetkisizKayitsiz() async throws {
            StubURLProtocol.reset { _ in (401, [:], Data()) }
            await #expect(throws: CloudSync.SyncError.notRegistered) {
                try await makeSync().upload(samples(1), plan: nil, identity: identity)
            }
        }
    }

    @Suite("ClaudeWebClient")
    struct WebClientShape {
        static let key = "sk-ant-" + String(repeating: "x", count: 24)

        /// Anahtar yenileme kancasının çağrılarını sayar.
        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var _values: [String] = []
            var values: [String] { lock.withLock { _values } }
            func append(_ value: String) { lock.withLock { _values.append(value) } }
        }

        func makeClient(onRotated: (@Sendable (String) -> Void)? = nil) -> ClaudeWebClient {
            ClaudeWebClient(sessionKey: Self.key, session: StubURLProtocol.session(),
                            onRotatedSessionKey: onRotated)
        }

        @Test("GET yalnızca 200 kabul eder: 204 badResponse(204) olur")
        func getYalniz200() async throws {
            StubURLProtocol.reset { _ in (204, [:], Data()) }
            await #expect(throws: ClaudeWebClient.ClientError.badResponse(204)) {
                _ = try await makeClient().rawUsage(organizationID: "org")
            }
        }

        @Test("GET 401 sessionExpired olur")
        func get401() async throws {
            StubURLProtocol.reset { _ in (401, [:], Data()) }
            await #expect(throws: ClaudeWebClient.ClientError.sessionExpired) {
                _ = try await makeClient().rawUsage(organizationID: "org")
            }
        }

        @Test("startSessionWindow 201'i kabul eder ve POST, POST, DELETE sırasıyla gider")
        func oturumPenceresi201() async throws {
            StubURLProtocol.reset { _ in (201, [:], Data()) }
            try await makeClient().startSessionWindow(organizationID: "org")

            let requests = StubURLProtocol.requests.map(\.request)
            #expect(requests.map(\.httpMethod) == ["POST", "POST", "DELETE"])
            let base = "/api/organizations/org/chat_conversations"
            #expect(requests.first?.url?.path == base)
            #expect(requests.dropFirst().first?.url?.path.hasSuffix("/completion") == true)
        }

        @Test("Set-Cookie ile gelen yeni sessionKey kancayı bir kez çağırır")
        func anahtarYenilenir() async throws {
            let rotated = "sk-ant-" + String(repeating: "y", count: 24)
            StubURLProtocol.reset { _ in
                (200, ["Set-Cookie": "sessionKey=\(rotated); Domain=.claude.ai; Path=/"], Data("{}".utf8))
            }
            let calls = Calls()
            _ = try await makeClient(onRotated: { calls.append($0) }).rawUsage(organizationID: "org")
            #expect(calls.values == [rotated])
        }

        @Test("Yabancı alan adından gelen sessionKey kancayı çağırmaz")
        func yabanciAlanCagirmaz() async throws {
            let rotated = "sk-ant-" + String(repeating: "z", count: 24)
            StubURLProtocol.reset { _ in
                (200, ["Set-Cookie": "sessionKey=\(rotated); Domain=.sahteclaude.ai; Path=/"], Data("{}".utf8))
            }
            let calls = Calls()
            _ = try await makeClient(onRotated: { calls.append($0) }).rawUsage(organizationID: "org")
            #expect(calls.values.isEmpty)
        }

        @Test("Set-Cookie mevcut anahtarla aynıysa kanca çağrılmaz")
        func ayniAnahtarCagirmaz() async throws {
            StubURLProtocol.reset { _ in
                (200, ["Set-Cookie": "sessionKey=\(Self.key); Domain=.claude.ai; Path=/"], Data("{}".utf8))
            }
            let calls = Calls()
            _ = try await makeClient(onRotated: { calls.append($0) }).rawUsage(organizationID: "org")
            #expect(calls.values.isEmpty)
        }

        @Test("Her istek headers(sessionKey:) içindeki tüm başlıkları taşır")
        func tumBasliklar() async throws {
            StubURLProtocol.reset { _ in (200, [:], Data("{}".utf8)) }
            let client = makeClient()
            _ = try await client.rawUsage(organizationID: "org")
            try await client.startSessionWindow(organizationID: "org")

            let expected = ClaudeWebClient.headers(sessionKey: Self.key)
            let requests = StubURLProtocol.requests.map(\.request)
            #expect(requests.count == 4)
            for request in requests {
                for (name, value) in expected {
                    #expect(request.value(forHTTPHeaderField: name) == value, "\(name)")
                }
            }
        }
    }
}
