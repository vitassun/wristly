import Foundation

// Coalesces small AVAudioEngine PCM buffers into ~240ms frames (7,680 bytes at 16 kHz 16-bit mono)
// to minimize radio wakeups and WebSocket packet overhead on Apple Watch.
struct PCMChunker: Sendable {
    let chunkSize: Int
    private var buffer = Data()

    init(chunkSize: Int = 7_680) {
        let clamped = max(2, min(chunkSize, 32_000))
        self.chunkSize = clamped - (clamped % 2)
        self.buffer.reserveCapacity(self.chunkSize)
    }

    mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        var chunks: [Data] = []
        var offset = 0
        while buffer.count - offset >= chunkSize {
            let end = offset + chunkSize
            chunks.append(Data(buffer[offset..<end]))
            offset = end
        }
        if offset > 0 {
            buffer = Data(buffer[offset...])
        }
        return chunks
    }

    mutating func flush() -> Data? {
        let evenCount = buffer.count - (buffer.count % 2)
        guard evenCount > 0 else {
            buffer.removeAll(keepingCapacity: false)
            return nil
        }
        let remainder = Data(buffer.prefix(evenCount))
        buffer.removeAll(keepingCapacity: false)
        return remainder
    }
}
