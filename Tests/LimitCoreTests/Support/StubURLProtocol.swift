import Foundation

/// Ağa çıkmadan istek biçimini yakalayan URLProtocol taslağı.
///
/// Durum statik ve paylaşımlı: bunu kullanan testler `.serialized` bir
/// üst takım altında toplanmalı, aksi hâlde işleyiciler birbirini ezer.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Kaydedilen istek ve gövdesi. URLSession gövdeyi çoğu zaman akışa
    /// çevirdiği için `httpBody` tek başına güvenilir değil.
    struct Recorded {
        let request: URLRequest
        let body: Data?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: ((URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) private static var _requests: [Recorded] = []

    static var handler: ((URLRequest) -> (Int, [String: String], Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    static var requests: [Recorded] {
        lock.withLock { _requests }
    }

    /// Her testin başında çağrılır: kayıtları siler, işleyiciyi kurar.
    static func reset(_ handler: @escaping (URLRequest) -> (Int, [String: String], Data)) {
        lock.withLock {
            _requests = []
            _handler = handler
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        let handler = Self.lock.withLock { () -> ((URLRequest) -> (Int, [String: String], Data))? in
            Self._requests.append(Recorded(request: request, body: body))
            return Self._handler
        }
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, headers, data) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
