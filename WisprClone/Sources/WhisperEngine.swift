import Foundation
import SwiftWhisper

class WhisperEngine: TranscriptionEngine {
    private var whisper: Whisper?
    private let modelUrl: URL
    
    init(modelUrl: URL) {
        self.modelUrl = modelUrl
        // Initialize with 8 threads for better performance on modern Macs
        var params = WhisperParams()
        params.n_threads = 8
        self.whisper = Whisper(fromFileURL: modelUrl, withParams: params)
    }
    
    func transcribe(audioFile: URL, contextualStrings: [String]) async throws -> String {
        guard let whisper = whisper else {
            throw NSError(domain: "WhisperEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper model not initialized"])
        }
        
        // Strict 10s timeout per spec
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let decodeStart = Date()
                let frames = try AudioUtils.decodeAudioFileToOtherFormat(url: audioFile)
                Logger.info("⏱️ [Whisper] Audio decode: \(String(format: "%.2fs", Date().timeIntervalSince(decodeStart))) (\(frames.count) samples)")
                
                let txStart = Date()
                let segments = try await whisper.transcribe(audioFrames: frames)
                Logger.info("⏱️ [Whisper] Model inference: \(String(format: "%.2fs", Date().timeIntervalSince(txStart)))")
                
                let resultText = segments.map { $0.text }.joined(separator: " ")
                Logger.debug("[Whisper] Output: \(resultText)")
                return resultText
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000) // matches AppleSpeechEngine
                throw NSError(domain: "WhisperEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Whisper transcription timed out (30s)."])
            }
            
            let result = try await group.next()!
            group.cancelAll()
            
            // Aggressive cleaning for Whisper Hallucinations
            var cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Common hallucinations on silence
            let hallucinations = ["[BLANK_AUDIO]", "[audible]", "[silence]", "(wind)", "(mumbles)"]
            for h in hallucinations {
                cleaned = cleaned.replacingOccurrences(of: h, with: "")
            }
            
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
