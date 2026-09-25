import Foundation
import SwiftWhisper

class WhisperEngine: TranscriptionEngine {
    private var whisper: Whisper?
    private let modelUrl: URL
    /// Guards the shared `whisper.params.initial_prompt` pointer
    private let promptLock = NSLock()
    
    /// Whisper has no contextual-strings API. An initial prompt that mentions the terms biases the
    /// decoder toward those spellings (e.g. "Groq" rather than "grok"). Returns nil when there are none.
    static func vocabularyPrompt(for words: [String]) -> String? {
        var seen = Set<String>()
        var terms: [String] = []
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            terms.append(trimmed)
        }
        guard !terms.isEmpty else { return nil }
        // Whisper only uses roughly the last 224 prompt tokens; keep well under that
        var prompt = "Glossary:"
        for term in terms {
            guard prompt.count + term.count + 2 < 600 else { break }
            prompt += (prompt.hasSuffix(":") ? " " : ", ") + term
        }
        return prompt + "."
    }
    
    init(modelUrl: URL) {
        self.modelUrl = modelUrl
        // Initialize with 8 threads for better performance on modern Macs
        var params = WhisperParams()
        params.n_threads = 8
        // With language left on "auto", whisper.cpp runs the encoder an extra time per clip just to
        // detect the language (measured: ~2x inference time). English-only models make that pointless.
        if modelUrl.lastPathComponent.contains(".en.") {
            params.language = .english
        }
        self.whisper = Whisper(fromFileURL: modelUrl, withParams: params)
    }
    
    func transcribe(audioFile: URL, duration: Double, contextualStrings: [String]) async throws -> String {
        guard let whisper = whisper else {
            throw NSError(domain: "WhisperEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper model not initialized"])
        }
        
        let prompt = Self.vocabularyPrompt(for: contextualStrings)
        
        // Dynamic Timeout: 5s overhead + 1.0x duration
        let timeout = max(5.0, duration * 1.0) + 5.0
        Logger.debug("Using dynamic timeout (Whisper): \(String(format: "%.1fs", timeout))")
        
        // Real timeout: returns at the deadline instead of waiting for inference to finish
        let result: String = try await withTimeout(
            seconds: timeout,
            timeoutError: { NSError(domain: "WhisperEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Whisper transcription timed out (\(Int(timeout))s)."]) }
        ) {
            let decodeStart = Date()
            let frames = try AudioUtils.decodeAudioFileToOtherFormat(url: audioFile)
            Logger.info("⏱️ [Whisper] Audio decode: \(String(format: "%.2fs", Date().timeIntervalSince(decodeStart))) (\(frames.count) samples)")
            
            // The C string must outlive the run, which can continue past our timeout,
            // so it is freed here when Whisper actually finishes rather than by the caller
            let promptPointer = prompt.flatMap { strdup($0) }
            self.promptLock.withLock {
                whisper.params.initial_prompt = promptPointer.map { UnsafePointer($0) }
            }
            defer {
                self.promptLock.withLock {
                    if whisper.params.initial_prompt == promptPointer.map({ UnsafePointer($0) }) {
                        whisper.params.initial_prompt = nil
                    }
                }
                free(promptPointer)
            }
            if let prompt = prompt {
                Logger.debug("[Whisper] Initial prompt: \(prompt)")
            }
            
            let txStart = Date()
            let segments = try await whisper.transcribe(audioFrames: frames)
            Logger.info("⏱️ [Whisper] Model inference: \(String(format: "%.2fs", Date().timeIntervalSince(txStart)))")
            
            let resultText = segments.map { $0.text }.joined(separator: " ")
            Logger.debug("[Whisper] Output: \(resultText)")
            return resultText
        }
        
        // Aggressive cleaning for Whisper Hallucinations
        var cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Common hallucinations on silence
        let hallucinations = ["[BLANK_AUDIO]", "[audible]", "[silence]", "(wind)", "(mumbles)"]
        for h in hallucinations {
            cleaned = cleaned.replacingOccurrences(of: h, with: "")
        }
        // On near-silent clips Whisper can echo its prompt back
        if let prompt = prompt {
            cleaned = cleaned.replacingOccurrences(of: prompt, with: "")
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
