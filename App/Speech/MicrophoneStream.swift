@preconcurrency import AVFoundation

/// Captures the microphone and hands out 16-bit mono PCM at a fixed rate (24 kHz for OpenAI
/// Realtime). Nothing is written to disk.
final class MicrophoneStream: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampleRate: Double
    private var converter: AVAudioConverter?

    init(sampleRate: Double = 24_000) {
        self.sampleRate = sampleRate
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts capturing; `onPCM` receives little-endian Int16 samples from the audio thread.
    func start(onPCM: @escaping @Sendable (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw SpeechError.audioFormat }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, _ in
            let ratio = target.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData else { return }
            onPCM(Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
