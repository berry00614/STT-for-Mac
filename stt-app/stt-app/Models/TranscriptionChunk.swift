import Foundation

/// A single chunk of streaming transcription output.
struct TranscriptionChunk: Codable, Identifiable {
    let id: Int
    let time: Double
    let text: String

    init(chunkNumber: Int, timeSeconds: Double, text: String) {
        self.id = chunkNumber
        self.time = timeSeconds
        self.text = text
    }

    /// Parse from JSON line output (matching stt stream --json format).
    /// Format: {"chunk": N, "time": T, "text": "..."}
    static func fromJSONLine(_ line: String) -> TranscriptionChunk? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TranscriptionChunk.self, from: data)
    }
}
