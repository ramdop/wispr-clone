import SwiftUI

@main
struct WisprCloneApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            switch appState.status {
            case .idle:
                Image(systemName: "waveform.circle")
                    .foregroundStyle(.primary)
            case .recording:
                Image(systemName: "recordingtape.circle.fill")
                    .foregroundStyle(.red)
            case .transcribing:
                Image(systemName: "hourglass.circle")
            case .processing:
                Image(systemName: "brain.head.profile")
            case .pasting:
                 Image(systemName: "arrow.right.doc.on.clipboard")
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
