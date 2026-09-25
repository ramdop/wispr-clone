import SwiftUI
import AppKit

class HUDOverlay: NSWindowController {
    static let shared = HUDOverlay()
    
    private let windowSize = CGSize(width: 160, height: 70) // Approx size
    
    init() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], // Borderless for custom shape
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating // Always on top
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // View has its own shadow
        
        super.init(window: panel)
        
        // Position at bottom center
        centerWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isSetUp = false
    
    /// Installs the SwiftUI content once; the view observes AppState for everything after that
    func setup(appState: AppState) {
        guard !isSetUp else { return }
        isSetUp = true
        
        let view = WaveformView(appState: appState)
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        self.window?.contentView = hostingView
        self.window?.backgroundColor = .clear
        
        // Hardcode a safe size for now, close to WaveformView's frame (60+20, 22+12) plus room for the toast
        self.window?.setContentSize(CGSize(width: 130, height: 60))
        centerWindow()
    }
    
    func show() {
        centerWindow()
        window?.orderFront(nil)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    private func centerWindow() {
        guard let screen = NSScreen.main else { return }
        
        let screenRect = screen.visibleFrame
        let width = window?.frame.width ?? windowSize.width
        let x = screenRect.midX - (width / 2)
        let y = screenRect.minY + 50 // Floating 50pts from bottom
        
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
