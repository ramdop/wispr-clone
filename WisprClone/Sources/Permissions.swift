import Foundation
import AVFoundation
import Speech
import ApplicationServices

class Permissions {
    static let shared = Permissions()
    
    // Check if we have Microphone access
    var hasMicrophoneAccess: Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    // Check if we have Speech Recognition access
    var hasSpeechAccess: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    // Check if we have Accessibility access (for key events/pasting)
    var hasAccessibilityAccess: Bool {
        return AXIsProcessTrusted()
    }
    
    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func requestSpeechAccess(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    func requestAccessibilityAccess() {
        // Use DispatchQueue to avoid crash when called from Terminal
        DispatchQueue.main.async {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
}
