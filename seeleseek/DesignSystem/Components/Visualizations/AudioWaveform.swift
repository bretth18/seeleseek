import SwiftUI

/// Animated audio waveform visualization (decorative)
struct AudioWaveform: View {
    let isPlaying: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let bars = 20
                let barWidth = size.width / CGFloat(bars)
                let maxHeight = size.height

                for i in 0..<bars {
                    let x = CGFloat(i) * barWidth
                    let heightFactor = isPlaying
                        ? (0.3 + 0.7 * sin(phase + CGFloat(i) * 0.5) * sin(phase * 2 + CGFloat(i) * 0.3))
                        : 0.2

                    let height = max(4, maxHeight * CGFloat(heightFactor))
                    let y = (size.height - height) / 2

                    let rect = CGRect(x: x + 1, y: y, width: barWidth - 2, height: height)
                    let path = RoundedRectangle(cornerRadius: 2).path(in: rect)

                    context.fill(path, with: .color(SeeleColors.accent))
                }
            }
        }
        .onAppear {
            if isPlaying {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: SeeleSpacing.md) {
        AudioWaveform(isPlaying: true)
            .frame(width: 200, height: 40)
        AudioWaveform(isPlaying: false)
            .frame(width: 200, height: 40)
    }
    .padding()
    .background(SeeleColors.background)
}
