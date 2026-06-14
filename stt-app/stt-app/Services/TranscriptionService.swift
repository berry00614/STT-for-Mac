import Foundation
import Combine
import SwiftUI

/// Coordinates real-time streaming transcription:
///   Audio capture → ring buffer → POST whisper-server → filtered text output
///
/// Implements the same three-layer anti-hallucination strategy as the Python CLI:
///   1. Energy gate (RMS threshold + sustained speech detection)
///   2. whisper no-speech-thold (server-side)
///   3. Hallucination text filter (post-processing)
@MainActor
final class TranscriptionService: ObservableObject {

    // MARK: - State

    @Published private(set) var isRunning = false
    @Published var displayText: String = ""
    @Published private(set) var currentStreamTime: Double = 0

    // MARK: - Configuration

    var streamInterval: TimeInterval { AppSettings.shared.captionsStreamInterval }
    var silenceThreshold: Float { Float(AppSettings.shared.captionsSilenceThreshold) }

    // MARK: - Dependencies

    let serverManager = WhisperServerManager()
    let audioCapture = AudioCaptureService()
    private var cancellables = Set<AnyCancellable>()
    private var streamTimer: Timer?
    private var lastText: String = ""
    private var silenceStreak: Int = 0
    private var allowPrint: Bool = false
    private let bytesPerSec: Int = 16000 * 2  // 16kHz × 16-bit mono

    // Energy gate parameters (matching Python CLI)
    private let speechWindow: TimeInterval = 1.5
    private let hangoverIntervals: Int = 3

    // MARK: - Lifecycle

    /// Start the streaming transcription pipeline.
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        displayText = ""
        lastText = ""
        silenceStreak = 0
        allowPrint = false

        // 1. Start whisper-server
        print("[Transcription] Starting whisper-server...")
        await serverManager.start()

        guard serverManager.isReady else {
            print("[Transcription] Server failed to start. State: \(serverManager.serverState)")
            isRunning = false
            return
        }

        // 2. Request microphone permission
        let hasPermission = await audioCapture.requestPermission()
        guard hasPermission else {
            print("[Transcription] Microphone permission denied")
            serverManager.stop()
            isRunning = false
            return
        }

        // 3. Start audio capture
        do {
            try audioCapture.start()
            print("[Transcription] Audio capture started (16kHz mono)")
        } catch {
            print("[Transcription] Audio capture failed: \(error)")
            serverManager.stop()
            isRunning = false
            return
        }

        // 4. Start periodic send timer
        let interval = streamInterval
        print("[Transcription] Starting send timer (interval: \(interval)s)")

        let timer = Timer(
            timeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sendChunk()
            }
        }
        streamTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        print("[Transcription] Pipeline started — streaming active")
    }

    /// Stop the streaming transcription pipeline.
    func stop() {
        print("[Transcription] Stopping pipeline...")
        isRunning = false
        streamTimer?.invalidate()
        streamTimer = nil
        audioCapture.stop()
        serverManager.stop()
        displayText = ""
        print("[Transcription] Pipeline stopped")
    }

    // MARK: - Chunk Processing

    private var chunkCount = 0

    private func sendChunk() async {
        guard isRunning, serverManager.isReady, audioCapture.state == .recording else { return }

        let ringData = audioCapture.accumulatedData

        // Cap at 60s to bound memory
        let maxBytes = 60 * bytesPerSec
        var capped = ringData
        if capped.count > maxBytes {
            capped = capped.subdata(in: (capped.count - 30 * bytesPerSec)..<capped.count)
        }

        guard capped.count >= bytesPerSec / 2 else {
            // Not enough audio yet
            return
        }

        // Energy gate: check only recent audio
        let recentLen = min(capped.count, Int(Double(bytesPerSec) * speechWindow))
        let recent = capped.subdata(in: (capped.count - recentLen)..<capped.count)
        let hasSpeech = AntiHallucination.hasSpeech(recent, threshold: silenceThreshold)

        if hasSpeech {
            silenceStreak = 0
            allowPrint = true
        } else {
            silenceStreak += 1
            if silenceStreak == 1 {
                allowPrint = true
            } else {
                allowPrint = false
            }
            if silenceStreak > hangoverIntervals {
                // Extended silence — skip this chunk entirely
                return
            }
        }

        // Build WAV and send to server
        let wav = AntiHallucination.buildWAV(pcmData: capped)
        chunkCount += 1
        let text = await serverManager.transcribe(
            wavData: wav,
            filename: "chunk_\(chunkCount).wav"
        )

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Log every 10th chunk for diagnostics
        if chunkCount % 10 == 0 {
            print("[Transcription] Chunk #\(chunkCount): buffer=\(capped.count/bytesPerSec)s, speech=\(hasSpeech), silenceStreak=\(silenceStreak), text=\(trimmed.prefix(50))")
        }

        // Filter
        if !trimmed.isEmpty,
           !AntiHallucination.isHallucination(trimmed),
           trimmed != lastText,
           allowPrint {

            displayText = trimmed
            currentStreamTime = Double(capped.count) / Double(bytesPerSec)
            print("[Transcription] → Display: \"\(trimmed.prefix(80))\"")
            lastText = trimmed
        }
    }
}
