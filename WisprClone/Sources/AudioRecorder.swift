import AVFoundation
import Accelerate

class AudioRecorder: NSObject {
    private let engine = AVAudioEngine()
    private var isRecording = false
    private var outputFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var framesWritten: Int64 = 0
    private var sampleRate: Double = 44100.0
    private var currentFileURL: URL?
    private var maxLevelSeen: Float = 0.0
    
    // Level meter throttling (audio thread only): the UI only needs ~20 updates/sec,
    // each update re-renders every view observing the level
    private static let levelUpdatesPerSecond: Double = 20
    private var levelFramesAccumulated: AVAudioFrameCount = 0
    private var levelPeakInWindow: Float = 0.0
    
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
        levelFramesAccumulated = 0
        levelPeakInWindow = 0.0
        let framesPerLevelUpdate = AVAudioFrameCount(format.sampleRate / Self.levelUpdatesPerSecond)
        
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
            guard let channelData = buffer.floatChannelData?.pointee, buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(channelData, vDSP_Stride(buffer.stride), &rms, vDSP_Length(buffer.frameLength))
            let level = min(max(rms * 15.0, 0), 1.0)
            self.maxLevelSeen = max(self.maxLevelSeen, level)
            
            // Emit the loudest level of each window instead of every buffer
            self.levelPeakInWindow = max(self.levelPeakInWindow, level)
            self.levelFramesAccumulated += buffer.frameLength
            if self.levelFramesAccumulated >= framesPerLevelUpdate {
                self.onAudioLevelUpdate?(self.levelPeakInWindow)
                self.levelFramesAccumulated = 0
                self.levelPeakInWindow = 0
            }
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
