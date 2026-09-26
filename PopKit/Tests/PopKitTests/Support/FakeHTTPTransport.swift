import Foundation
@testable import PopKit

/// A scriptable `HTTPTransport` for Server tests: each call to `send` is handed to the
/// current responder and recorded, so a test can both control the reply and assert on
/// what was actually sent (URL, headers, body).
actor FakeHTTPTransport: HTTPTransport {
    typealias Responder = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private var responder: Responder
    private(set) var requests: [URLRequest] = []

    init(responder: @escaping Responder) {
        self.responder = responder
    }

    /// Always returns the same envelope body with the given HTTP status.
    static func json(_ status: Int = 200, body: String) -> FakeHTTPTransport {
        FakeHTTPTransport { request in
            (Data(body.utf8), .fake(status: status, url: request.url!))
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try responder(request)
    }

    func setResponder(_ responder: @escaping Responder) {
        self.responder = responder
    }

    var requestCount: Int { requests.count }
    var lastRequest: URLRequest? { requests.last }
}

extension HTTPURLResponse {
    static func fake(status: Int, url: URL = URL(string: "https://pop.example/functions/v1/story-turn")!) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
