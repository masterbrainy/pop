import Foundation
import PopKit
import Security

/// Everything that talks to the outside world, built once at launch: anonymous sign-in, the
/// server functions, the page pipeline, and the local cache of pictures (ROADMAP §2).
@MainActor
final class AppServices {
    let server: (any PopServer)?
    let pipeline: PagePipeline?
    let media = MediaCache()

    /// Nil when the Supabase settings are missing from the build (Supabase.local.xcconfig).
    static let shared = AppServices()

    private init() {
        guard let config = AppConfig.load() else {
            AppLog.scene.error("Supabase settings missing; live generation is off")
            server = nil
            pipeline = nil
            return
        }
        let transport = URLSessionHTTPTransport()
        let auth = AnonymousAuth(supabaseURL: config.supabaseURL, publishableKey: config.publishableKey, transport: transport, store: KeychainSessionStore())
        let server = HTTPPopServer(supabaseURL: config.supabaseURL, publishableKey: config.publishableKey, transport: transport, auth: auth)
        self.server = server
        pipeline = PagePipeline(server: server)
    }

    var isOnline: Bool { server != nil }
}

/// The Supabase URL and publishable key, injected through Info.plist from the git-ignored xcconfig.
struct AppConfig {
    let supabaseURL: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> AppConfig? {
        guard let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let url = URL(string: urlString), url.scheme == "https",
              let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String, !key.isEmpty
        else { return nil }
        return AppConfig(supabaseURL: url, publishableKey: key)
    }
}

/// Keeps the anonymous Supabase session in the Keychain, so a relaunch keeps the same user
/// (and so the same books and rate-limit bucket).
struct KeychainSessionStore: SessionStore {
    private static let account = "supabase-session"
    private static let service = "com.masterbrainy.pop"

    func load() async -> StoredSession? {
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func save(_ session: StoredSession?) async {
        SecItemDelete(Self.baseQuery as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var query = Self.baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { AppLog.scene.error("keychain save failed: \(status)") }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

/// Downloads generated pictures from their signed URLs into Application Support, so pages
/// show from disk and saved books work offline.
actor MediaCache {
    private let directory = URL.applicationSupportDirectory.appending(path: "media", directoryHint: .isDirectory)

    /// Downloads `url` and returns the absolute file path the book stores as `stillPath`.
    func store(from url: URL, named name: String) async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let file = directory.appending(path: name)
        try data.write(to: file, options: .atomic)
        return file.path(percentEncoded: false)
    }

    func write(_ data: Data, named name: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name)
        try data.write(to: file, options: .atomic)
        return file.path(percentEncoded: false)
    }
}
