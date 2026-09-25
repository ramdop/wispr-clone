import Foundation
import SwiftUI
import ServiceManagement
import Carbon
import CoreGraphics

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case processing
    case pasting
    case error(String)
}

enum WhisperModel: String, Codable, CaseIterable {
    case base = "Base (Standard)"
    case small = "Small (Balanced)"
    case medium = "Medium (High Accuracy)"
    
    var filename: String {
        switch self {
        // Use English-only models (.en) for ~3-5x faster transcription
        case .base: return "ggml-base.en.bin"
        case .small: return "ggml-small.en.bin"
        case .medium: return "ggml-medium.en.bin"
        }
    }
    
    var downloadUrl: URL {
        let base = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
        return URL(string: base + filename)!
    }
}

/// Mic level for the recording waveform. Kept out of AppState so ~20 Hz level updates
/// only re-render the waveform, not every view observing AppState.
@MainActor
final class AudioLevelMeter: ObservableObject {
    @Published var level: Float = 0.0
}

@MainActor
class AppState: ObservableObject, HotKeyDelegate {
    @Published var status: AppStatus = .idle {
        didSet {
            updateHUD()
        }
    }
    
    @Published var lastTranscript: String = "No transcription yet."
    @Published var removeFillers: Bool = true
    @Published var addPunctuation: Bool = true
    @Published var useSmartFlow: Bool = true {
        didSet {
            UserDefaults.standard.set(useSmartFlow, forKey: "useSmartFlow")
        }
    }
    
    @Published var selectedLLMProvider: LLMProviderType = .groq {
        didSet {
            UserDefaults.standard.set(selectedLLMProvider.rawValue, forKey: "selectedLLMProvider")
        }
    }
    
    @Published var openaiApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(openaiApiKey, forKey: "llmApiKey_openai")
        }
    }
    
    @Published var groqApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(groqApiKey, forKey: "llmApiKey_groq")
        }
    }
    
    @Published var hasMicAccess: Bool = false
    @Published var hasSpeechAccess: Bool = false
    @Published var hasAccessibilityAccess: Bool = false
    
    let audioMeter = AudioLevelMeter()
    @Published var processingDuration: Double?
    
    // LLM & Snippets
    let llmService = LLMService()
    @Published var isLLMAvailable: Bool = false
    @Published var snippetStore = SnippetStore()
    @Published var customVocabularyStore = CustomVocabularyStore()
    @Published var learnedDictionaryStore = LearnedDictionaryStore()
    private let latencyTracker = LatencyTracker.shared
    
    // Active correction session
    private var activeCorrectionSession: CorrectionSession?
    // Bumped per paste so a slow focus capture can't start a session for an older paste
    private var correctionGeneration = 0
    
    @Published var highPerformanceMode: Bool = UserDefaults.standard.bool(forKey: "highPerformanceMode") {
        didSet {
            UserDefaults.standard.set(highPerformanceMode, forKey: "highPerformanceMode")
        }
    }
    
    @Published var useSnippets: Bool = true {
        didSet {
            UserDefaults.standard.set(useSnippets, forKey: "useSnippets")
        }
    }
    
    // Transcription Engine
    @Published var selectedEngine: TranscriptionProvider = .apple {
        didSet {
            updateTranscriberAndCheckStatus()
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: "selectedEngine")
        }
    }
    
    @Published var selectedModel: WhisperModel = .base {
        didSet {
            updateTranscriberAndCheckStatus()
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }
    
    // Model Management
    @Published var isModelDownloaded: Bool = false
    @Published var isDownloadingModel: Bool = false
    @Published var downloadProgress: Double = 0.0
    
    private func getModelUrl(for model: WhisperModel) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WisprClone/models/\(model.filename)")
    }
    
    // Launch at Login (macOS 13+)
    @Published var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLogin()
        }
    }
    
    private func updateLaunchAtLogin() {
        do {
            if #available(macOS 13.0, *) {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            }
        } catch {
            Logger.error("Failed to update Launch at Login: \(error)")
        }
    }
    
    private let permissions = Permissions.shared
    private let recorder = AudioRecorder()
    private let transcriber = SpeechTranscriber()
    private var hotKey: HotKey?
    
    private var permissionTimer: Timer?
    private var processingStartTime: Date?
    
    // Notifications
    @Published var notificationMessage: String?
    private var notificationTimer: Timer?
    
    init() {
        // Bound every AX call into other apps (system default is ~6s per call)
        FocusCapture.configureMessagingTimeout()
        
        // Load preferences
        if let savedEngine = UserDefaults.standard.string(forKey: "selectedEngine"),
           let engine = TranscriptionProvider(rawValue: savedEngine) {
            self.selectedEngine = engine
        }
        
        if let savedModel = UserDefaults.standard.string(forKey: "selectedModel"),
           let model = WhisperModel(rawValue: savedModel) {
            self.selectedModel = model
        }
        
        // Default to Smart Flow: Enabled
        self.useSmartFlow = UserDefaults.standard.object(forKey: "useSmartFlow") == nil ? true : UserDefaults.standard.bool(forKey: "useSmartFlow")
        
        // Default to LLM: Groq
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedLLMProvider"),
           let provider = LLMProviderType(rawValue: savedProvider) {
            self.selectedLLMProvider = provider
        } else {
            self.selectedLLMProvider = .groq
        }
        
        self.openaiApiKey = UserDefaults.standard.string(forKey: "llmApiKey_openai") ?? ""
        self.groqApiKey = UserDefaults.standard.string(forKey: "llmApiKey_groq") ?? ""
        
        // Setup Dictionary Promotion Callback
        learnedDictionaryStore.onEntryPromoted = { [weak self] entry in
            DispatchQueue.main.async {
                self?.showToast("Learned: \(entry.canonical)")
            }
        }
        
        // Check initial permissions
        checkPermissions()
        
        // Setup mic monitoring
        setupAudioMonitoring()
        
        // Observe HotKey changes
        updateHotKey()

        self.useSnippets = UserDefaults.standard.object(forKey: "useSnippets") == nil ? true : UserDefaults.standard.bool(forKey: "useSnippets")
        
        checkPermissions()
        
        // Check Launch at Login status
        if SMAppService.mainApp.status == .enabled {
            launchAtLogin = true
        }
        

        setupRecorder()
        startPermissionPolling()
        
        // Initial setup for engine
        updateTranscriberAndCheckStatus()
        
        // Setup learned dictionary notifications
        setupLearnedDictionaryNotifications()
        
        Task {
            await checkLLMAvailability()
        }
    }
    
    func checkLLMAvailability() async {
        let available = await llmService.isProviderAvailable(.ollama)
        await MainActor.run {
            self.isLLMAvailable = available
        }
    }
    
    deinit {
        permissionTimer?.invalidate()
    }
    
    func showToast(_ message: String) {
        notificationMessage = message
        notificationTimer?.invalidate()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.notificationMessage = nil
            }
        }
    }
    
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPermissions()
            }
        }
    }
    
    func checkPermissions() {
        hasMicAccess = permissions.hasMicrophoneAccess
        hasSpeechAccess = permissions.hasSpeechAccess
        hasAccessibilityAccess = permissions.hasAccessibilityAccess
    }
    
    func requestPermissions() {
        if !hasMicAccess {
            permissions.requestMicrophoneAccess { [weak self] granted in
                self?.hasMicAccess = granted
            }
        }
        
        if !hasSpeechAccess {
            permissions.requestSpeechAccess { [weak self] granted in
                self?.hasSpeechAccess = granted
            }
        }
        
        if !hasAccessibilityAccess {
            permissions.requestAccessibilityAccess()
        }
    }
    
    func setupAudioMonitoring() {
        // Placeholder for audio level monitoring setup if distinct from setupRecorder
    }
    
    func updateHotKey() {
        hotKey = HotKey()
        hotKey?.delegate = self
    }

    private func setupRecorder() {
        recorder.onRecordingFinished = { [weak self] url in
            Task {
                await self?.processRecording(url: url)
            }
        }
        
        let meter = audioMeter
        recorder.onAudioLevelUpdate = { level in
            DispatchQueue.main.async {
                meter.level = level
            }
        }
    }
    
    // MARK: - HotKeyDelegate
    
    nonisolated func hotKeyDown(mode: InputMode) {
        Logger.info("[AppState] HotKey Down detected! Mode: \(mode)")
        Task { @MainActor in
            startRecording(mode: mode)
        }
    }
    
    nonisolated func hotKeyUp(mode: InputMode) {
        Task { @MainActor in
            stopRecording()
        }
    }
    
    // MARK: - Actions
    
    // Inputs for Command Mode
    var currentInputMode: InputMode = .dictation
    var contextText: String?
    private var keyPollingTimer: Timer?
    private var keyReleaseCount: Int = 0
    
    func startRecording(mode: InputMode = .dictation) {
        let startInit = Date()
        
        // Allow recording from idle or any error state
        switch status {
        case .idle, .error:
            break
        default:
            return
        }
        
        guard permissions.hasMicrophoneAccess else {
            setError("Microphone access missing")
            requestPermissions() // Proactively request if not granted
            return
        }
        
        currentInputMode = mode
        
        // FIRST: Capture context BEFORE changing status (which shows the HUD)
        var contextTime: Double = 0
        if mode == .command {
            let contextStart = Date()
            if let text = ContextManager.getSelectedText() {
                self.contextText = text
                Logger.info("Context captured: \(text.prefix(50))...")
            } else {
                Logger.info("No context captured.")
                self.contextText = nil 
            }
            contextTime = Date().timeIntervalSince(contextStart)
        } else {
            self.contextText = nil
        }
        
        // THEN: Update status (this triggers HUD show)
        audioMeter.level = 0
        status = .recording
        processingDuration = nil // Reset duration
        playHaptic()
        do {
            try recorder.start()
            startKeyPolling()
            
            let totalStartLatency = Date().timeIntervalSince(startInit)
            Logger.info("🚀 Start Latency: Mode=\(mode), ContextCapture=\(String(format: "%.3fs", contextTime)), TotalStart=\(String(format: "%.3fs", totalStartLatency))")
        } catch {
            setError("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    /// Backup for the Carbon hotkey-released event (primary stop signal, handled in hotKeyUp),
    /// which is unreliable for modifier chords.
    private func startKeyPolling() {
        keyReleaseCount = 0
        keyPollingTimer?.invalidate()
        // Timer fires on the main run loop
        keyPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self = self else { return timer.invalidate() }
                
                // Use HID System State (Hardware) for truth
                let isSpaceDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Space))
                
                if isSpaceDown {
                    self.keyReleaseCount = 0
                } else {
                    self.keyReleaseCount += 1
                    // Debounce: require 3 consecutive hits (~90ms) of "key up" to stop
                    // This prevents premature stops from HID polling glitches while
                    // ensuring we stop quickly even if the Carbon event is lost.
                    if self.keyReleaseCount >= 3 {
                        Logger.debug("Polling (HID): Spacebar released (debounced). Stopping.")
                        self.stopRecording()
                    }
                }
            }
        }
    }
    
    private func playHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    
    func stopRecording() {
        keyPollingTimer?.invalidate()
        keyPollingTimer = nil
        
        guard status == .recording else { return }
        status = .processing
        recorder.stop()
        playHaptic()
    }
    
    private func processRecording(url: URL) async {
        Logger.info("Processing recording at: \(url.path)")
        let totalStartTime = Date()
        status = .transcribing
        
        // 1. Capture State on Main Actor
        let contextWords = highPerformanceMode ? [] : customVocabularyStore.words
        let rFillers = removeFillers
        let aPunctuation = addPunctuation
        let uSnippets = useSnippets
        let uSmartFlow = useSmartFlow
        let cInputMode = currentInputMode
        let llmProvider = selectedLLMProvider
        let oaiKey = openaiApiKey
        let gKey = groqApiKey
        let cText = contextText
        let llmAvail = isLLMAvailable
        let isHighPerf = highPerformanceMode
        let engineName = transcriber.currentProvider.rawValue
        let latencyTracker = self.latencyTracker
        // Capture dependencies locally to avoid MainActor isolation issues in detached task
        let transcriber = self.transcriber
        let llmService = self.llmService
        let dictEntries = learnedDictionaryStore.entries
        
        // 2. Detach processing to background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let sessionID = UUID().uuidString
            // Header read only (no decode), so this adds nothing measurable to the pipeline
            let clipDuration = AudioUtils.duration(of: url)
            var transcriptionTime: Double = 0
            var llmTime: Double = 0
            
            do {
                // --- TRANSCRIPTION ---
                let txStart = Date()
                // Use captured 'transcriber'
                let text = try await transcriber.transcribe(audioFile: url, duration: clipDuration, contextualStrings: contextWords)
                transcriptionTime = Date().timeIntervalSince(txStart)
                Logger.info("⏱️ Transcription: \(String(format: "%.2fs", transcriptionTime))")
                Logger.debug("📝 Raw Transcription: '\(text)'")
                
                // --- CLEANUP ---
                let cleanStart = Date()
                var cleaned = TextCleaner.clean(text: text,
                                                removeFillers: rFillers,
                                                addPunctuation: aPunctuation)
                
                cleaned = TextCleaner.formatDictation(cleaned)
                
                if uSnippets {
                // Quick hop to MainActor for SnippetStore access (safest if not sendable)
                let textToExpand = cleaned
                cleaned = await MainActor.run {
                     return self.snippetStore.expandTriggers(in: textToExpand)
                }
            }
                Logger.info("⏱️ Cleanup+Snippets: \(String(format: "%.2fs", Date().timeIntervalSince(cleanStart)))")
                
                // --- LLM PROCESSING ---
                if !cleaned.isEmpty {
                    if uSmartFlow || cInputMode == .command {
                        let llmStart = Date()
                        if llmProvider == .ollama && !llmAvail {
                            Logger.warning("Smart Flow skipped: Ollama unavailable")
                        } else {
                            // Update status to processing on Main Thread
                            await MainActor.run {
                                self.status = .processing
                            }
                            
                            Logger.info("Sending to LLM (\(llmProvider.rawValue))...")
                            let key = llmProvider == .openai ? oaiKey : gKey
                            
                            if cInputMode == .command {
                                if let context = cText {
                                    let combinedInput = """
                                    Input Selection: "\(context)"
                                    Input Instruction: "\(cleaned)"
                                    """
                                    // Use captured 'llmService'
                                    cleaned = try await llmService.process(combinedInput, provider: llmProvider, apiKey: key, template: .command)
                                } else {
                                    Logger.error("Command Mode Error: No context to operate on.")
                                    throw NSError(domain: "WisprClone", code: 404, userInfo: [NSLocalizedDescriptionKey: "Command Mode Failed: No text selected."])
                                }
                            } else {
                                // Use dictionary-aware template if we have learned entries or custom vocabulary
                                if !dictEntries.isEmpty || !contextWords.isEmpty {
                                    // Format dictionary entries for LLM
                                    let dictText = dictEntries.map { entry in
                                        "\(entry.aliases.joined(separator: " / ")) → \(entry.canonical)"
                                    }.joined(separator: "\n")
                                    
                                    // Format custom vocabulary bias
                                    let vocabText = contextWords.joined(separator: ", ")
                                    
                                    // Create custom template with dictionary and vocab bias
                                    let templateWithDict = PromptTemplate(rawValue:
                                        PromptTemplate.smartFlowWithDictionary.rawValue
                                            .replacingOccurrences(of: "%DICTIONARY_ENTRIES%", with: dictText.isEmpty ? "None" : dictText)
                                            .replacingOccurrences(of: "%CUSTOM_VOCABULARIES%", with: vocabText.isEmpty ? "None" : vocabText)
                                    )
                                    Logger.info("📚 Including \(dictEntries.count) dict entries and \(contextWords.count) vocab words in LLM prompt")
                                    
                                    cleaned = try await llmService.process(cleaned, provider: llmProvider, apiKey: key, template: templateWithDict)
                                } else {
                                    // No dictionary entries and no custom vocab, use standard template
                                    cleaned = try await llmService.process(cleaned, provider: llmProvider, apiKey: key)
                                }
                            }
                        }
                        llmTime = Date().timeIntervalSince(llmStart)
                        Logger.info("⏱️ LLM Processing: \(String(format: "%.2fs", llmTime)) [Provider: \(llmProvider.rawValue)]")
                    } else {
                    // Smart Flow disabled - apply dictionary replacements
                    // Hop to MainActor for safety accessing learnedDictionaryStore methods
                    let textToReplace = cleaned
                    let learnedApplied = await MainActor.run {
                        return self.learnedDictionaryStore.applyReplacements(to: textToReplace)
                    }
                    if learnedApplied != cleaned {
                            Logger.info("📖 Applied learned dictionary (regex fallback): '\(cleaned.prefix(30))...' → '\(learnedApplied.prefix(30))...'")
                            cleaned = learnedApplied
                        }
                    }
                }
                
                let finalCleaned = cleaned
                let duration = Date().timeIntervalSince(totalStartTime)
                let tTime = transcriptionTime
                let lTime = llmTime
                
                // --- FINAL UI UPDATE & PASTE ---
                await MainActor.run {
                    self.lastTranscript = finalCleaned
                    self.processingDuration = duration
                    Logger.info("Total Pipeline: \(String(format: "%.2fs", duration))")
                    
                    // Paste first. Focus capture for correction learning makes blocking AX calls into
                    // the target app, so it runs afterwards and off the main thread.
                    var injectTime: Double = 0
                    if !finalCleaned.isEmpty {
                        self.status = .pasting
                        let injectionStart = Date()
                        TextInjector.inject(text: finalCleaned)
                        injectTime = Date().timeIntervalSince(injectionStart)
                        Logger.info("⏱️ Injection completed")
                        // High Performance mode skips AX focus capture (and so correction learning)
                        if !isHighPerf {
                            self.beginCorrectionLearning(injectedText: finalCleaned)
                        }
                    }
                    
                    // Ready for the next dictation immediately
                    self.status = .idle
                    
                    // Written on the tracker's own background queue
                    latencyTracker.record(
                        sessionID: sessionID,
                        clipDuration: clipDuration,
                        decodeTime: 0,
                        prosodyTime: 0,
                        transcriptionTime: tTime,
                        llmTime: lTime,
                        injectionTime: injectTime,
                        totalLatency: duration,
                        engine: engineName,
                        mode: cInputMode.description
                    )
                }
                
            } catch {
                let errorMsg = error.localizedDescription
                
                // Record failure metrics
                latencyTracker.record(
                    sessionID: sessionID,
                    clipDuration: clipDuration,
                    decodeTime: 0,
                    prosodyTime: 0,
                    transcriptionTime: transcriptionTime,
                    llmTime: llmTime,
                    injectionTime: 0,
                    totalLatency: Date().timeIntervalSince(totalStartTime),
                    engine: engineName,
                    mode: cInputMode.description,
                    status: "error",
                    errorMessage: errorMsg
                )
                
                Logger.error("Processing failed: \(errorMsg)")
                await MainActor.run {
                    self.setError(errorMsg)
                }
            }
            
            // Cleanup: Remove the recording file after processing (success or failure)
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func updateHUD() {
        // Lazy one-time setup
        HUDOverlay.shared.setup(appState: self)
        
        switch status {
        case .idle, .error:
            HUDOverlay.shared.hide()
        case .recording, .transcribing, .processing, .pasting:
            HUDOverlay.shared.show()
        }
    }
    
    func setError(_ message: String) {
        self.status = .error(message)
        // Debug Logging
        let logUrl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/wispr_verify_error.log")
        let logMsg = "\(Date()): \(message)\n"
        if let data = logMsg.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logUrl.path) {
                if let handle = try? FileHandle(forWritingTo: logUrl) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logUrl)
            }
        }
    }
    
    private let downloader = ModelDownloader()
    
    func checkModelStatus() {
        let url = getModelUrl(for: selectedModel)
        isModelDownloaded = FileManager.default.fileExists(atPath: url.path)
    }
    
    private func updateTranscriberAndCheckStatus() {
        let url = getModelUrl(for: selectedModel)
        transcriber.setProvider(selectedEngine, modelUrl: url)
        
        if selectedEngine == .whisper {
            checkModelStatus()
        }
    }
    
    func downloadWhisperModel() {
        guard !isModelDownloaded && !isDownloadingModel else { return }
        
        isDownloadingModel = true
        
        Task {
            let url = selectedModel.downloadUrl
            let finalUrl = getModelUrl(for: selectedModel)
            
            // Poll progress
            let progressTask = Task {
                for await _ in Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().values {
                    if !self.isDownloadingModel { break }
                    self.downloadProgress = await self.downloader.progress
                }
            }
            
            do {
                let tempUrl = try await downloader.download(from: url)
                
                // Move from temp to final
                try FileManager.default.createDirectory(at: finalUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Remove existing if any
                if FileManager.default.fileExists(atPath: finalUrl.path) {
                    try FileManager.default.removeItem(at: finalUrl)
                }
                try FileManager.default.moveItem(at: tempUrl, to: finalUrl)
                
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.isModelDownloaded = true
                    self.downloadProgress = 1.0
                    self.updateTranscriberAndCheckStatus()
                }
                progressTask.cancel()
                
            } catch {
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.setError("Download failed: \(error.localizedDescription)")
                }
                progressTask.cancel()
            }
        }
    }
    
    // MARK: - Correction Learning
    
    /// Capture the focused field off the main thread, then watch it for user corrections
    private func beginCorrectionLearning(injectedText: String) {
        // A new paste supersedes any session still watching the previous one
        activeCorrectionSession?.cancel()
        activeCorrectionSession = nil
        correctionGeneration += 1
        let generation = correctionGeneration
        
        Task.detached(priority: .utility) { [weak self] in
            guard let focusInfo = FocusCapture.captureCurrentFocus() else {
                Logger.debug("[CorrectionLearning] No focused element captured; skipping session")
                return
            }
            await MainActor.run {
                guard let self = self, self.correctionGeneration == generation else { return }
                self.startCorrectionSession(injectedText: injectedText, focusInfo: focusInfo)
            }
        }
    }
    
    private func startCorrectionSession(injectedText: String, focusInfo: FocusInfo) {
        // Cancel any existing session
        activeCorrectionSession?.cancel()
        
        let session = CorrectionSession(injectedText: injectedText, focusInfo: focusInfo)
        activeCorrectionSession = session
        
        session.start { [weak self, weak session] result in
            Task { @MainActor in
                guard let self = self else { return }
                if let session = session, self.activeCorrectionSession === session {
                    self.activeCorrectionSession = nil
                }
                if let result = result {
                    self.processCorrectionResult(result)
                }
            }
        }
    }
    
    private func processCorrectionResult(_ result: CorrectionResult) {
        Logger.info("[CorrectionLearning] Session ended. Injected: '\(result.injectedText.prefix(50))...' | Corrected: '\(result.correctedText.prefix(50))...'")
        
        // Skip if no change
        if result.injectedText == result.correctedText {
            Logger.debug("[CorrectionLearning] No correction detected (text unchanged)")
            return
        }
        
        // Extract replacement candidate
        guard let candidate = CorrectionDiff.extractReplacement(injected: result.injectedText, corrected: result.correctedText) else {
            Logger.debug("[CorrectionLearning] Could not extract valid replacement (diff too large or invalid)")
            return
        }
        
        Logger.info("[CorrectionLearning] Candidate extracted: '\(candidate.from)' → '\(candidate.to)'")
        
        // Check learning heuristics
        guard CorrectionDiff.shouldLearn(candidate) else {
            Logger.debug("[CorrectionLearning] Candidate rejected: failed heuristic checks")
            return
        }
        
        Logger.info("✅ [CorrectionLearning] Recording correction: '\(candidate.from)' → '\(candidate.to)' (bundleID: \(result.bundleID ?? "nil"))")
        learnedDictionaryStore.recordCorrection(candidate, bundleID: result.bundleID)
    }
    
    func setupLearnedDictionaryNotifications() {
        learnedDictionaryStore.onEntryPromoted = { [weak self] entry in
            Task { @MainActor in
                self?.showLearnedNotification(entry: entry)
            }
        }
    }
    
    private func showLearnedNotification(entry: LearnedEntry) {
        // Show via HUD or system notification
        let alias = entry.aliases.first ?? "?"
        let message = "Learned: '\(alias)' → '\(entry.canonical)'"
        Logger.info("🎉 \(message)")
        
        // Update lastTranscript temporarily to show feedback (simple approach)
        let previousTranscript = lastTranscript
        lastTranscript = "✅ \(message)"
        
        // Restore after a delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                if self.lastTranscript.hasPrefix("✅") {
                    self.lastTranscript = previousTranscript
                }
            }
        }
    }
}

