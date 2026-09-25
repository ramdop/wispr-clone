import SwiftUI

struct WaveformView: View {
    @ObservedObject var appState: AppState
    
    // Animation state
    @State private var phase: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            if let message = appState.notificationMessage {
                // Toast Notification
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                    .id("toast_\(message)") // Force redraw on message change
            } else if appState.status == .recording {
                RecordingWaveform(meter: appState.audioMeter, phase: phase)
            } else {
                // Processing / Pasting State
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .symbolEffect(.pulse.byLayer, options: .repeating) // iOS 17/macOS 14+ animation
            }
        }
        .frame(width: 60, height: 22) // Unified compact size
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Dark frosted capsule so the white content reads over light and dark apps alike
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.55)
            }
            .clipShape(Capsule())
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.6), location: 0.0),
                            .init(color: .white.opacity(0.1), location: 0.3),
                            .init(color: .clear, location: 0.5),
                            .init(color: .white.opacity(0.3), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

/// Observes only the audio meter, so ~20 Hz level updates re-render just the bars
struct RecordingWaveform: View {
    @ObservedObject var meter: AudioLevelMeter
    let phase: CGFloat
    
    var body: some View {
        HStack(spacing: 3) {
            // Chromatic Aberration Effect: 3 Layers
            ZStack {
                // Red Layer
                WaveformLayer(color: .red.opacity(0.8), audioLevel: meter.level, phase: phase)
                    .offset(x: -3 * CGFloat(meter.level))
                    .blur(radius: 0.5)
                
                // Blue Layer
                WaveformLayer(color: .blue.opacity(0.8), audioLevel: meter.level, phase: phase)
                    .offset(x: 3 * CGFloat(meter.level))
                    .blur(radius: 0.5)
                
                // Green/White Core Layer
                WaveformLayer(color: .white, audioLevel: meter.level, phase: phase)
            }
        }
    }
}

struct WaveformLayer: View {
    let color: Color
    let audioLevel: Float
    let phase: CGFloat
    
    let count = 7 // Reduced density for smaller size
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                // Bars logic
                let relativeIndex = CGFloat(i) / CGFloat(count)
                
                // Mix two sine waves for organic movement
                let sine1 = sin(relativeIndex * .pi * 2 + phase * 3)
                let sine2 = cos(relativeIndex * .pi * 1.5 + phase * 2)
                let combinedSine = (sine1 + sine2) / 2
                
                // Base height small
                let baseHeight: CGFloat = 3
                
                // Dynamic Audio Response
                let visualLevel = CGFloat(audioLevel)
                let responsiveLevel = pow(visualLevel, 0.8)
                
                // Center bias
                let centerBias = 1.0 - abs(0.5 - relativeIndex)
                
                // Final Height calculation - smaller for compact pill
                let dynamicHeight: CGFloat = 14 * responsiveLevel * centerBias
                
                // Modulate with wave
                let waveHeight = baseHeight + (dynamicHeight * (0.4 + 0.6 * (combinedSine + 1) / 2))
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 2.5, height: min(max(waveHeight, 3), 18)) // Cap height
            }
        }
    }
}
