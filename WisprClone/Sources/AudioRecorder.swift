import AVFoundation

class AudioRecorder: NSObject {
    private let engine = AVAudioEngine()
    private var isRecording = false
    private var outputFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var framesWritten: Int64 = 0
    private var sampleRate: Double = 44100.0
    private var currentFileURL: URL?
    private var maxLevelSeen: Float = 0.0
    
    var onRecordingFinished: ((URL) -> Void)?
    var onAudioLevelUpdate: ((Float) -> Void)?
    
    override init() {
        super.init()
    }
    
    func start() throws {
        guard !isRecording else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        framesWritten = 0
        maxLevelSeen = 0.0
        
        // Create temp file with unique name to avoid race conditions
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueID = UUID().uuidString
        let fileURL = tempDir.appendingPathComponent("recording_\(uniqueID).caf")
        self.currentFileURL = fileURL
        
        outputFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // Write to file
            do {
                try self.outputFile?.write(from: buffer)
                self.framesWritten += Int64(buffer.frameLength)
            } catch {
                Logger.error("[AudioRecorder] Buffer write failed: \(error.localizedDescription)")
            }
            
            // Calculate Level (RMS) for Visuals
            let channelDataValue = buffer.floatChannelData?.pointee
            let channelDataValueArray = stride(from: 0, 
                                             to: Int(buffer.frameLength),
                                             by: buffer.stride).map{ channelDataValue?[$0] ?? 0 }
            
            // Calculate RMS
            let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
            let level = min(max(rms * 15.0, 0), 1.0)
            
            self.onAudioLevelUpdate?(level)
            self.maxLevelSeen = max(self.maxLevelSeen, level)
        }
        
        engine.prepare()
        try engine.start()
        isRecording = true
        recordingStartTime = Date()
        Logger.info("[AudioRecorder] Started recording at \(Date())")
    }
    
    func stop() {
        guard isRecording else { return }
        
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let audioDuration = Double(framesWritten) / sampleRate
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil // Close file
        isRecording = false
        
        Logger.info("[AudioRecorder] Stopped. Wall clock: \(String(format: "%.2fs", duration)), Audio frames: \(framesWritten), Audio duration: \(String(format: "%.2fs", audioDuration)), Max level: \(String(format: "%.2f", maxLevelSeen))")
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = currentFileURL ?? tempDir.appendingPathComponent("recording.caf")
        
        onRecordingFinished?(fileURL)
        currentFileURL = nil
    }
}
