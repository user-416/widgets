import Foundation

/// Plug into URLSession via configuration.protocolClasses to return canned
/// responses for given URL prefixes. Lets us test the Strava client
/// without hitting the real APIs.
final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe counter for asserting how many times an `@Sendable` test
/// closure ran. Avoids Swift 6 strict-concurrency errors that come from
/// capturing a plain `var` inside a sendable closure.
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() {
        lock.lock(); defer { lock.unlock() }
        n += 1
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return n
    }
}
