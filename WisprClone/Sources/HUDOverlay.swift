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
    
    func setup(appState: AppState) {
        let view = WaveformView(appState: appState)
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        self.window?.contentView = hostingView
        self.window?.backgroundColor = .clear
        
        // Resize window
        // Hardcode a safe size for now, close to WaveformView's frame (90+32, 28+16) ~ 122x44
        let newSize = CGSize(width: 130, height: 60)
        
        // Center again with new size
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (newSize.width / 2)
            let y = screenRect.minY + 50
            self.window?.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: newSize), display: true)
        }
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
        let x = screenRect.midX - (windowSize.width / 2)
        let y = screenRect.minY + 50 // Floating 50pts from bottom
        
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
