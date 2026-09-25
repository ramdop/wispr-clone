import Foundation
import AVFoundation

class AudioUtils {
    enum AudioError: Error {
        case fileNotFound
        case formatError
        case processingError
    }
    
    /// Clip length in seconds, read from the file header (no decoding)
    static func duration(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Decodes an audio file to an array of Floats (16kHz, Mono) required by Whisper
    static func decodeAudioFileToOtherFormat(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        
        // Whisper requires 16kHz PCM
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw AudioError.formatError
        }
        
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw AudioError.formatError
        }
        
        let frameCount = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        
        var error: NSError?
        _ = converter.convert(to: buffer, error: &error) { packetCount, outStatus in
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: packetCount)!
            
            do {
                try file.read(into: inputBuffer, frameCount: packetCount)
                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }
        
        if let error = error {
            throw error
        }
        
        guard let channelData = buffer.floatChannelData else {
            throw AudioError.processingError
        }
        
        let channelDataValue = channelData.pointee
        let frames = Array(UnsafeBufferPointer(start: channelDataValue, count: Int(buffer.frameLength)))
        
        return frames
    }
}
