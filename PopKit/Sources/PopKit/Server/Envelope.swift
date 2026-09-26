import Foundation

/// Every Edge Function reply uses one envelope (docs/CONTRACTS.md §3):
/// `{"ok":true,"data":{…}}` or `{"ok":false,"error":{"code":"…","message":"…"}}`.
/// `Envelope.decode` turns the raw HTTP body into a `Result` without ever throwing.
public enum ServerError: Error, Equatable, Sendable {
    case unauthorized(String)
    case forbidden(String)
    case rateLimited(String)
    case badRequest(String)
    case unsafe(String)
    case upstream(String)
    case internalError(String)
    /// The request never reached (or never came back from) the server: no connection, timed out, DNS, etc.
    case transport(String)
    /// The body wasn't the envelope shape, or `data`/`error` didn't decode into the expected type.
    case decoding(String)

    /// A short, parent-facing message. Never the raw server or system text (that stays in `serverDetail`).
    public var message: String {
        switch self {
        case .unauthorized: "Please sign in again."
        case .forbidden: "You don't have access to that."
        case .rateLimited: "Pop! is taking a quick breather — try again in a moment."
        case .badRequest: "Something about that request didn't look right."
        case .unsafe: "Let's try a different direction for the story."
        case .upstream: "Pop!'s storyteller is having trouble right now. Please try again."
        case .internalError: "Something went wrong on our end. Please try again."
        case .transport: "Couldn't reach Pop!. Check your connection and try again."
        case .decoding: "Pop! sent something unexpected. Please try again."
        }
    }

    /// The raw server or system text, kept for logs — never shown to a parent directly.
    public var serverDetail: String {
        switch self {
        case let .unauthorized(text), let .forbidden(text), let .rateLimited(text), let .badRequest(text),
            let .unsafe(text), let .upstream(text), let .internalError(text), let .transport(text), let .decoding(text):
            text
        }
    }

    fileprivate static func server(code: String, message: String) -> ServerError {
        switch code {
        case "unauthorized": .unauthorized(message)
        case "forbidden": .forbidden(message)
        case "rate_limited": .rateLimited(message)
        case "bad_request": .badRequest(message)
        case "unsafe": .unsafe(message)
        case "upstream": .upstream(message)
        case "internal": .internalError(message)
        default: .internalError(message)
        }
    }
}

public enum Envelope {
    private struct Wire<T: Decodable>: Decodable {
        let ok: Bool
        let data: T?
        let error: WireError?
    }

    private struct WireError: Decodable {
        let code: String
        let message: String
    }

    /// Decodes one Edge Function HTTP body into `T`, or a `ServerError` describing why it couldn't.
    public static func decode<T: Decodable>(_ data: Data, as type: T.Type) -> Result<T, ServerError> {
        let wire: Wire<T>
        do {
            wire = try JSONDecoder().decode(Wire<T>.self, from: data)
        } catch {
            return .failure(.decoding("\(error)"))
        }

        if wire.ok, let payload = wire.data {
            return .success(payload)
        }
        if !wire.ok, let error = wire.error {
            return .failure(.server(code: error.code, message: error.message))
        }
        return .failure(.decoding("envelope had ok=\(wire.ok) but no matching data/error"))
    }
}
