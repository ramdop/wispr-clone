import Speech
import Foundation

protocol TranscriptionEngine {
    func transcribe(audioFile: URL, duration: Double, contextualStrings: [String]) async throws -> String
}

enum TranscriptionProvider: String, Codable {
    case apple
    case whisper
}

class SpeechTranscriber {
    private var engine: TranscriptionEngine
    var currentProvider: TranscriptionProvider
    
    init(provider: TranscriptionProvider = .apple) {
        self.currentProvider = provider
        switch provider {
        case .apple:
            self.engine = AppleSpeechEngine()
        case .whisper:
            // Default to Apple until setProvider is called with a model
            self.engine = AppleSpeechEngine() 
        }
    }
    
    func setProvider(_ provider: TranscriptionProvider, modelUrl: URL? = nil) {
        self.currentProvider = provider
        switch provider {
        case .apple:
            self.engine = AppleSpeechEngine()
        case .whisper:
            if let url = modelUrl, FileManager.default.fileExists(atPath: url.path) {
                self.engine = WhisperEngine(modelUrl: url)
                Logger.info("Switched to Whisper Engine: \(url.lastPathComponent)")
            } else {
                Logger.warning("Whisper model not provided or not found.")
                self.engine = AppleSpeechEngine()
            }
        }
    }
    
    func transcribe(audioFile: URL, duration: Double, contextualStrings: [String] = []) async throws -> String {
        return try await engine.transcribe(audioFile: audioFile, duration: duration, contextualStrings: contextualStrings)
    }
}

class AppleSpeechEngine: TranscriptionEngine {
    private let recognizer: SFSpeechRecognizer?
    
    init() {
        // Use system locale, fallback to en-US if nil
        let locale = Locale.current
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    func transcribe(audioFile: URL, duration: Double, contextualStrings: [String]) async throws -> String {
        guard let recognizer = recognizer else {
            throw NSError(domain: "AppleSpeechEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer not available"])
        }
        
        if !recognizer.isAvailable {
            throw NSError(domain: "AppleSpeechEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recognizer is currently unavailable"])
        }
        
        // Dynamic Timeout: 5s overhead + 1.0x duration
        // e.g., 2s audio -> 10s timeout
        // e.g., 20s audio -> 25s timeout
        let timeout = max(5.0, duration * 1.0) + 5.0
        Logger.debug("Using dynamic timeout: \(String(format: "%.1fs", timeout)) for duration: \(String(format: "%.1fs", duration))")
        
        // Real timeout: returns at the deadline even if the recognizer never calls back
        return try await withTimeout(
            seconds: timeout,
            timeoutError: { NSError(domain: "AppleSpeechEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Transcription timed out (\(Int(timeout))s)."]) }
        ) { () async throws -> String in
            try await self.performTranscription(recognizer: recognizer, audioFile: audioFile, contextualStrings: contextualStrings)
        }
    }
    
    private func performTranscription(recognizer: SFSpeechRecognizer, audioFile: URL, contextualStrings: [String]) async throws -> String {
        let state = RecognitionState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.begin(continuation) {
                    let request = SFSpeechURLRecognitionRequest(url: audioFile)
                    request.shouldReportPartialResults = false
                    
                    if recognizer.supportsOnDeviceRecognition {
                        // Prefer on-device for speed and stability
                        request.requiresOnDeviceRecognition = true
                    }
                    
                    request.contextualStrings = contextualStrings
                    Logger.debug("SFSpeech: Added \(contextualStrings.count) contextual strings (OnDevice: \(request.requiresOnDeviceRecognition))")
                    
                    return recognizer.recognitionTask(with: request) { result, error in
                        if let error = error {
                            state.finish(.failure(error))
                            return
                        }
                        
                        if let result = result, result.isFinal {
                            Logger.debug("SFSpeech: Final result received: \(result.bestTranscription.formattedString.prefix(50))...")
                            state.finish(.success(result.bestTranscription.formattedString))
                        }
                    }
                }
            }
        } onCancel: {
            Logger.debug("SFSpeech: Transcription task cancelled")
            state.cancel()
        }
    }
}

/// Owns the continuation and the SFSpeechRecognitionTask so that the continuation is resumed
/// exactly once (the recognizer can call back more than once) and cancellation actually
/// stops recognition instead of leaving it running.
private final class RecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var cancelled = false
    
    func begin(_ continuation: CheckedContinuation<String, Error>, start: () -> SFSpeechRecognitionTask) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
        
        let task = start()
        
        lock.lock()
        self.task = task
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            task.cancel()
        }
    }
    
    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
    
    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        task?.cancel()
        continuation?.resume(throwing: CancellationError())
    }
}
