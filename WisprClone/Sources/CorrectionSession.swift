import ApplicationServices
import Foundation

/// Result of a correction capture session
struct CorrectionResult {
    let injectedText: String
    let correctedText: String
    let bundleID: String?
}

/// Manages a short-lived session to observe user corrections after paste
class CorrectionSession {
    private let injectedText: String
    private let focusInfo: FocusInfo
    private var observer: AXObserver?
    private var idleTimer: Timer?
    private var hardStopTimer: Timer?
    
    private var latestSnapshot: String
    private var completion: ((CorrectionResult?) -> Void)?
    
    private let idleSettleDelay: TimeInterval = 3.0 // 3 seconds - give user time to correct
    private let hardStopDelay: TimeInterval = 20.0  // 20 seconds
    
    init(injectedText: String, focusInfo: FocusInfo) {
        self.injectedText = injectedText
        self.focusInfo = focusInfo
        self.latestSnapshot = focusInfo.initialValue ?? ""
    }
    
    deinit {
        cleanup()
    }
    
    /// Start observing for corrections
    /// Completion is called with result when session ends (either by idle settle or hard stop)
    func start(completion: @escaping (CorrectionResult?) -> Void) {
        self.completion = completion
        
        // Create AX observer
        var observerRef: AXObserver?
        let createResult = AXObserverCreate(focusInfo.pid, axCallback, &observerRef)
        
        guard createResult == .success, let obs = observerRef else {
            Logger.error("[CorrectionSession] Failed to create AXObserver: \(createResult.rawValue)")
            completion(nil)
            return
        }
        
        self.observer = obs
        
        // Add notification for value changes
        let addResult = AXObserverAddNotification(obs, focusInfo.element, kAXValueChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        
        if addResult != .success {
            Logger.debug("[CorrectionSession] Failed to add value notification: \(addResult.rawValue)")
            // Continue anyway - we'll use timer-based snapshots as fallback
        }
        
        // Add observer to run loop
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        
        // Start hard stop timer
        hardStopTimer = Timer.scheduledTimer(withTimeInterval: hardStopDelay, repeats: false) { [weak self] _ in
            self?.endSession(reason: "hard stop")
        }
        
        // Start initial idle timer
        restartIdleTimer()
        
        Logger.debug("[CorrectionSession] Started observing for corrections (bundleID: \(focusInfo.bundleID ?? "unknown"))")
    }
    
    /// Called when AX notification is received (from C callback)
    func handleValueChanged() {
        // Snapshot current value
        if let value = FocusCapture.readValue(from: focusInfo.element) {
            latestSnapshot = value
        }
        
        // Restart idle timer
        restartIdleTimer()
    }
    
    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleSettleDelay, repeats: false) { [weak self] _ in
            self?.endSession(reason: "idle settle")
        }
    }
    
    private func endSession(reason: String) {
        Logger.debug("[CorrectionSession] Ending session: \(reason)")
        
        // Take final snapshot
        if let value = FocusCapture.readValue(from: focusInfo.element) {
            latestSnapshot = value
        }
        
        cleanup()
        
        // Produce result
        let result = CorrectionResult(
            injectedText: injectedText,
            correctedText: latestSnapshot,
            bundleID: focusInfo.bundleID
        )
        
        completion?(result)
        completion = nil
    }
    
    private func cleanup() {
        idleTimer?.invalidate()
        idleTimer = nil
        hardStopTimer?.invalidate()
        hardStopTimer = nil
        
        if let obs = observer {
            AXObserverRemoveNotification(obs, focusInfo.element, kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        observer = nil
    }
    
    /// Cancel the session without producing a result
    func cancel() {
        cleanup()
        completion?(nil)
        completion = nil
    }
}

// MARK: - AX Callback (C function)

private func axCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon = refcon else { return }
    let session = Unmanaged<CorrectionSession>.fromOpaque(refcon).takeUnretainedValue()
    
    // Handle on main thread
    DispatchQueue.main.async {
        session.handleValueChanged()
    }
}
