import ApplicationServices
import Foundation

/// Result of a correction capture session
struct CorrectionResult {
    let injectedText: String
    let correctedText: String
    let bundleID: String?
}

/// Manages a short-lived session to observe user corrections after paste.
///
/// Must be created, started, and cancelled on the main thread. AX reads of the target field
/// happen on a background queue: they are round-trips into another app and can block, which
/// used to freeze the HUD and delay hotkey handling (hotkey events run on the main thread).
class CorrectionSession {
    private let injectedText: String
    private let focusInfo: FocusInfo
    private var observer: AXObserver?
    private var idleTimer: Timer?
    private var hardStopTimer: Timer?

    private var latestSnapshot: String
    private var completion: ((CorrectionResult?) -> Void)?
    private var isFinished = false

    // At most one snapshot read in flight; changes during a read collapse into one follow-up read
    private var snapshotInFlight = false
    private var snapshotPending = false

    private static let axQueue = DispatchQueue(label: "com.wispr.correction-ax", qos: .utility)

    private let idleSettleDelay: TimeInterval = 3.0 // 3 seconds - give user time to correct
    private let hardStopDelay: TimeInterval = 20.0  // 20 seconds

    init(injectedText: String, focusInfo: FocusInfo) {
        self.injectedText = injectedText
        self.focusInfo = focusInfo
        self.latestSnapshot = focusInfo.initialValue ?? ""
    }

    deinit {
        tearDown()
    }

    /// Start observing for corrections
    /// Completion is called with result when session ends (either by idle settle or hard stop)
    func start(completion: @escaping (CorrectionResult?) -> Void) {
        self.completion = completion
        
        // Timers start immediately; the observer is registered in the background
        hardStopTimer = Timer.scheduledTimer(withTimeInterval: hardStopDelay, repeats: false) { [weak self] _ in
            self?.endSession(reason: "hard stop")
        }
        restartIdleTimer()
        
        // Registering the notification is an IPC round-trip into the target app and can block
        let pid = focusInfo.pid
        let element = focusInfo.element
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        CorrectionSession.axQueue.async { [weak self] in
            var observerRef: AXObserver?
            let createResult = AXObserverCreate(pid, axCallback, &observerRef)
            
            guard createResult == .success, let obs = observerRef else {
                Logger.warning("[CorrectionSession] Failed to create AXObserver: \(createResult.rawValue)")
                return // Idle/hard-stop timers still end the session with a final snapshot
            }
            
            let addResult = AXObserverAddNotification(obs, element, kAXValueChangedNotification as CFString, refcon)
            if addResult != .success {
                Logger.debug("[CorrectionSession] Failed to add value notification: \(addResult.rawValue)")
                // Continue anyway - the final snapshot at session end still captures corrections
            }
            
            DispatchQueue.main.async {
                // Attach only if the session is still live; the unretained refcon must not outlive it
                guard let self = self, !self.isFinished else {
                    CorrectionSession.axQueue.async {
                        AXObserverRemoveNotification(obs, element, kAXValueChangedNotification as CFString)
                    }
                    return
                }
                self.observer = obs
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
                Logger.debug("[CorrectionSession] Started observing for corrections (bundleID: \(self.focusInfo.bundleID ?? "unknown"))")
            }
        }
    }
    
    /// Called on the main thread when an AX value-changed notification is received
    func handleValueChanged() {
        guard !isFinished else { return }
        restartIdleTimer()
        requestSnapshot()
    }

    /// Snapshot the field value off the main thread, coalescing bursts of changes
    private func requestSnapshot() {
        guard !snapshotInFlight else {
            snapshotPending = true
            return
        }
        snapshotInFlight = true

        let element = focusInfo.element
        CorrectionSession.axQueue.async { [weak self] in
            let value = FocusCapture.readValue(from: element)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.snapshotInFlight = false
                guard !self.isFinished else { return }
                if let value = value {
                    self.latestSnapshot = value
                }
                if self.snapshotPending {
                    self.snapshotPending = false
                    self.requestSnapshot()
                }
            }
        }
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleSettleDelay, repeats: false) { [weak self] _ in
            self?.endSession(reason: "idle settle")
        }
    }

    private func endSession(reason: String) {
        guard !isFinished else { return }
        isFinished = true
        Logger.debug("[CorrectionSession] Ending session: \(reason)")

        tearDown()

        // Take final snapshot off the main thread; the serial queue orders it after any in-flight read
        let element = focusInfo.element
        CorrectionSession.axQueue.async {
            let value = FocusCapture.readValue(from: element)
            DispatchQueue.main.async {
                if let value = value {
                    self.latestSnapshot = value
                }

                // Produce result
                let result = CorrectionResult(
                    injectedText: self.injectedText,
                    correctedText: self.latestSnapshot,
                    bundleID: self.focusInfo.bundleID
                )

                self.completion?(result)
                self.completion = nil
            }
        }
    }

    /// Stop timers and AX notifications. Idempotent.
    private func tearDown() {
        idleTimer?.invalidate()
        idleTimer = nil
        hardStopTimer?.invalidate()
        hardStopTimer = nil

        if let obs = observer {
            // Detach from the run loop now (local) so no more callbacks arrive;
            // unregistering is IPC, so do it in the background
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
            let element = focusInfo.element
            CorrectionSession.axQueue.async {
                AXObserverRemoveNotification(obs, element, kAXValueChangedNotification as CFString)
            }
        }
        observer = nil
    }

    /// Cancel the session without producing a result
    func cancel() {
        isFinished = true
        tearDown()
        completion?(nil)
        completion = nil
    }
}

// MARK: - AX Callback (C function)

private func axCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon = refcon else { return }
    // The observer's run loop source is on the main run loop, so this already runs on the main
    // thread. Handle synchronously: deferring with an async hop could outlive the (unretained) session.
    let session = Unmanaged<CorrectionSession>.fromOpaque(refcon).takeUnretainedValue()
    session.handleValueChanged()
}
