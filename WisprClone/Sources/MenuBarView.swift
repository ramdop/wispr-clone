import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Status
            HStack {
                Text("Wispr Clone")
                    .font(.headline)
                Spacer()
                statusView
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Tab Switcher
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Snippets").tag(1)
                Text("Dict").tag(2) // Future Dictionary placeholder
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if selectedTab == 0 {
                        generalSettings
                    } else if selectedTab == 1 {
                        SnippetsTab(appState: appState)
                    } else {
                        DictionaryTab(appState: appState)
                    }
                }
                .padding()
            }
            .frame(height: 400) // Fixed height to keep it stable as requested
            
            Divider()
            
            // Footer
            HStack {
                Text("Control (^) + Space to record")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
        }
        .frame(width: 300)
    }
    
    @ViewBuilder
    var generalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Last Transcript
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Last Transcript:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let duration = appState.processingDuration {
                        Text(String(format: "(%.1fs)", duration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(appState.lastTranscript, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
                Text(appState.lastTranscript)
                    .font(.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                
                if case .error(let message) = appState.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .textSelection(.enabled)
                } else if let warning = appState.smartFlowWarning {
                    Text("⚠️ Smart Flow failed, pasted unformatted: \(warning)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            
            Divider()
            
            // Settings
            Toggle("Remove Fillers", isOn: $appState.removeFillers)
            Toggle("Auto-Punctuation", isOn: $appState.addPunctuation)
            
            Toggle("Smart Flow", isOn: $appState.useSmartFlow)
                .toggleStyle(.switch)
            
            if appState.useSmartFlow {
                Picker("Provider", selection: $appState.selectedLLMProvider) {
                    ForEach(LLMProviderType.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
                if appState.selectedLLMProvider == .ollama {
                    if !appState.isLLMAvailable {
                        Text("⚠️ Ollama not detected at localhost:11434")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else if appState.selectedLLMProvider == .openai {
                    SecureField("OpenAI API Key", text: $appState.openaiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                } else if appState.selectedLLMProvider == .groq {
                    SecureField("Groq API Key", text: $appState.groqApiKey)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    TextField("Groq Model (default: \(GroqProvider.defaultModel))", text: $appState.groqModel)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .help("Model ID from console.groq.com/docs/models. Leave empty for \(GroqProvider.defaultModel).")
                }
            }
            
            Divider()
            
            // Engine Selection
            Picker("Engine", selection: $appState.selectedEngine) {
                Text("Apple (Fastest)").tag(TranscriptionProvider.apple)
                Text("Whisper (Smartest)").tag(TranscriptionProvider.whisper)
            }
            .pickerStyle(.radioGroup)
            
            // Model Management UI
            if appState.selectedEngine == .whisper {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .padding(.vertical, 2)
                
                if appState.isDownloadingModel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloading \(appState.selectedModel.rawValue)...")
                            .font(.caption)
                        ProgressView(value: appState.downloadProgress)
                            .progressViewStyle(.linear)
                    }
                } else if !appState.isModelDownloaded {
                    Button(action: {
                        appState.downloadWhisperModel()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Download Model")
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Model Ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            Toggle("Launch at Login", isOn: $appState.launchAtLogin)
            Toggle("High Performance (Disable Context)", isOn: $appState.highPerformanceMode)
                .help("Disables Accessibility focus capture and Custom Vocabulary for maximum speed.")
            
            Divider()
            
            // Permissions Check
            if !allPermissionsGranted {
                VStack(alignment: .leading) {
                    Text("Permissions Missing:")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if !appState.hasMicAccess { Text("• Microphone").font(.caption) }
                    if !appState.hasSpeechAccess { Text("• Speech Recognition").font(.caption) }
                    if !appState.hasAccessibilityAccess { Text("• Accessibility").font(.caption) }
                    
                    Button("Request Permissions") {
                        performRequestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    var allPermissionsGranted: Bool {
        appState.hasMicAccess && appState.hasSpeechAccess && appState.hasAccessibilityAccess
    }
    
    @ViewBuilder
    var statusView: some View {
        switch appState.status {
        case .idle:
            Text("Idle")
                .foregroundStyle(.secondary)
        case .recording:
            Text("Recording...")
                .foregroundStyle(.red)
        case .transcribing:
            Text(appState.selectedEngine == .whisper ? "Transcribing (Whisper)..." : "Transcribing (Apple)...")
                .foregroundStyle(.blue)
        case .processing:
            Text("Processing (Smart Flow)...")
                .foregroundStyle(.purple)
        case .pasting:
            Text("Pasting...")
                .foregroundStyle(.green)
        case .error(let msg):
            Text("Error")
                .foregroundStyle(.red)
                .help(msg)
        }
        }
    
    private func performDownload(_ state: AppState) {
        // state.downloadWhisperModel()
    }
    
    private func performRequestPermissions() {
        appState.requestPermissions()
        Logger.info("Request permissions triggered manually")
    }
}
