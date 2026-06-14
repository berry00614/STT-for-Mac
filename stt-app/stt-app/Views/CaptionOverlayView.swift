import SwiftUI

/// The floating live caption text display inside the overlay window.
struct CaptionOverlayView: View {
    @ObservedObject var transcriptionService: TranscriptionService

    var body: some View {
        VStack(spacing: 0) {
            if transcriptionService.isRunning {
                TranscriptionTextView(text: transcriptionService.displayText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(8)
    }
}

/// The actual text rendering area with dynamic font size.
struct TranscriptionTextView: View {
    let text: String

    @AppStorage("captions_font_size") var fontSize: Double = 20.0
    @AppStorage("captions_max_lines") var maxLines: Int = 3

    var body: some View {
        HStack {
            if text.isEmpty {
                Text("Listening...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                    .italic()
            } else {
                Text(text)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(maxLines)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// NSViewRepresentable wrapping NSVisualEffectView for macOS vibrancy/glass effect.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
