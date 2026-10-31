@preconcurrency import AVFoundation
import Foundation

// The tap runs on AVAudioEngine's audio thread. Conversion stays on that thread;
// the bounded stream transfers owned PCM bytes to the network task.
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var tapped = false

    func start() throws -> AsyncThrowingStream<Data, Error> {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        let node = engine.inputNode
        let input = node.outputFormat(forBus: 0)
        guard input.sampleRate > 0, input.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw ClientError.message("麦克风当前不可用")
        }
        let (stream, sink) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingNewest(20))
        continuation = sink
        node.installTap(onBus: 0, bufferSize: 4_800, format: input) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / input.sampleRate)) + 32
            guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: pcm, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if let error { sink.finish(throwing: error); return }
            guard pcm.frameLength > 0, let samples = pcm.int16ChannelData?[0] else { return }
            let data = Data(bytes: samples, count: Int(pcm.frameLength) * MemoryLayout<Int16>.size)
            if case .dropped = sink.yield(data) {
                sink.finish(throwing: ClientError.message("语音上传速度不足，请在网络稳定时重试"))
            }
        }
        tapped = true
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
        return stream
    }

    func stop() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        continuation?.finish(); continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
