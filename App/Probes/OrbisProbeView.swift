import Observation
import PopKit
import SwiftUI

/// Probe 0.3a: does Reactor's WebRTC video play in a WKWebView on the Duo simulator?
/// Uses a short-lived token that `scripts/dev-token.sh` drops into Documents (the API
/// key never enters the app), animates one picture, and disconnects after
/// `-probeSeconds` of video so the session stops billing. Results go to
/// `Documents/probe-orbis.log`; lines starting with RESULT are the measurements.
struct OrbisProbeView: View {
    @State private var probe = OrbisProbe()

    var body: some View {
        ZStack {
            Color.black
            if let still = probe.still {
                Image(uiImage: still).resizable().scaledToFit()
            }
            LiveSceneView(bridge: probe.bridge)
            overlay
        }
        .ignoresSafeArea()
        .task {
            await probe.setUp()
            if LaunchOptions.autorun { await probe.run() }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(probe.statsLine)
            Spacer()
            ForEach(Array(probe.recent.enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(2)
            }
            HStack {
                Button("Run") { Task { await probe.run() } }.disabled(probe.running)
                Button("Stop") { Task { await probe.stop() } }
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 48)
    }
}

@MainActor
@Observable
final class OrbisProbe {
    enum ProbeError: LocalizedError {
        case missingFile(String, hint: String)

        var errorDescription: String? {
            switch self {
            case let .missingFile(name, hint): "Documents/\(name) is missing: \(hint)"
            }
        }
    }

    let bridge = LiveSceneBridge()
    private(set) var recent: [String] = []
    private(set) var statsLine = "stats –"
    private(set) var still: UIImage?
    private(set) var running = false

    @ObservationIgnored private let log = FileLog(name: "probe-orbis")
    @ObservationIgnored private var listening = false
    @ObservationIgnored private var firstFrameAt: ContinuousClock.Instant?
    @ObservationIgnored private var stopRequested = false

    private static let recentLimit = 18
    private static let noFrameLimit: Duration = .seconds(120)
    private static let defaultPrompt = "The same sunny meadow with a small red fox under a big oak tree, the same locked-off, still camera. The fox's tail swishes slowly and the grass and flowers sway gently in the breeze. Nothing new enters the scene. Continuous slow motion, no cuts."

    func setUp() async {
        listen()
        still = (try? Data(contentsOf: Self.documents("probe-still.jpg"))).flatMap(UIImage.init(data:))
        do {
            try await bridge.load()
            try await bridge.setFit("contain")
        } catch {
            note("FAILED page load: \(error.localizedDescription)")
        }
    }

    func run() async {
        guard !running else { return }
        running = true
        stopRequested = false
        firstFrameAt = nil
        do {
            let token = try readToken()
            let stillData = try read("probe-still.jpg", hint: "copy a 16:9 JPEG there (scripts/probe-orbis.sh does)")
            let prompt = (try? String(contentsOf: Self.documents("probe-prompt.txt"), encoding: .utf8)) ?? Self.defaultPrompt
            note("connecting…")
            let connected = try await bridge.connect(jwt: token)
            note("RESULT connect \(connected.connectMs) ms, session \(connected.sessionId ?? "?")")
            let prepared = try await bridge.prepare(still: stillData, mimeType: "image/jpeg", prompt: prompt)
            note("RESULT prepare (upload → set_image → set_prompt → conditions_ready) \(prepared.prepareMs) ms, model image \(prepared.width ?? 0)×\(prepared.height ?? 0)")
            let startMs = try await bridge.start()
            note("RESULT start → generation_started \(startMs) ms")
            try await holdVideo()
        } catch {
            note("FAILED \(error.localizedDescription)")
        }
        await stop()
        running = false
    }

    func stop() async {
        stopRequested = true
        do {
            try await bridge.disconnect()
            note("disconnected")
        } catch {
            note("FAILED disconnect: \(error.localizedDescription)")
        }
    }

    /// Keeps generating for `-probeSeconds` after the first frame, or gives up if none arrives.
    private func holdVideo() async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let hold = Duration.seconds(LaunchOptions.probeSeconds)
        while !stopRequested {
            if let first = firstFrameAt, clock.now - first >= hold {
                note("RESULT held \(LaunchOptions.probeSeconds) s of video")
                return
            }
            if firstFrameAt == nil, clock.now - startedAt >= Self.noFrameLimit {
                note("RESULT no video frame within \(Self.noFrameLimit) of start")
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func listen() {
        guard !listening else { return }
        listening = true
        let events = bridge.events
        Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: SceneEvent) {
        switch event {
        case .stats:
            statsLine = event.summary
            log.append(event.summary)
        case .firstFrame:
            if firstFrameAt == nil { firstFrameAt = .now }
            note("RESULT \(event.summary)")
        default:
            note(event.summary)
        }
    }

    private func note(_ line: String) {
        log.append(line)
        AppLog.probe.log("ORBIS \(line, privacy: .public)")
        recent = Array((recent + [line]).suffix(Self.recentLimit))
    }

    /// Reads and deletes the dev token, so it doesn't outlive the run on disk.
    private func readToken() throws -> String {
        let data = try read("dev-reactor-token", hint: "run scripts/dev-token.sh")
        do {
            try FileManager.default.removeItem(at: Self.documents("dev-reactor-token"))
        } catch {
            note("could not delete the dev token file: \(error.localizedDescription)")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func read(_ name: String, hint: String) throws -> Data {
        guard let data = try? Data(contentsOf: Self.documents(name)), !data.isEmpty else {
            throw ProbeError.missingFile(name, hint: hint)
        }
        return data
    }

    private static func documents(_ name: String) -> URL {
        URL.documentsDirectory.appending(path: name)
    }
}
