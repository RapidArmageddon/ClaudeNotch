import SwiftUI

struct NotchPillView: View {
    @ObservedObject var monitor: ClaudeStateMonitor
    @State private var shakeOffset: CGFloat = 0

    let notchWidth: CGFloat
    let leftExtensionWidth: CGFloat
    let rightExtensionWidth: CGFloat
    let notchHeight: CGFloat

    private let claudeOrange = Color(red: 0.85, green: 0.45, blue: 0.25)
    private let cornerRadius: CGFloat = 12

    private var pillContent: (label: String, icon: String)? {
        switch monitor.state {
        case .idle:
            return nil
        case .launching:
            return ("Starting", "bolt.fill")
        case .processing(let tool):
            if let tool {
                return (tool, "gearshape.fill")
            }
            return ("Thinking", "sparkles")
        case .waitingForInput:
            return ("Waiting", "hand.raised.fill")
        case .error:
            return ("Stopped", "exclamationmark.triangle.fill")
        }
    }

    private var isActive: Bool { pillContent != nil }
    private var isProcessing: Bool {
        if case .processing = monitor.state { return true }
        return false
    }
    private var totalWidth: CGFloat { leftExtensionWidth + notchWidth + rightExtensionWidth }

    var body: some View {
        if notchWidth > 0 {
            notchedLayout
        } else {
            floatingLayout
        }
    }

    private var notchedLayout: some View {
        ZStack {
            if let content = pillContent {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)
                .frame(width: totalWidth, height: notchHeight)

                // Icon on the left — uses low-fps opacity pulse instead of scaleEffect
                HStack {
                    pulsingIcon(name: content.icon)
                        .frame(width: leftExtensionWidth)
                    Spacer()
                }
                .frame(width: totalWidth, height: notchHeight)

                // Text on the right
                HStack {
                    Spacer()
                    Text(content.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .frame(width: rightExtensionWidth, alignment: .leading)
                        .padding(.leading, 8)
                }
                .frame(width: totalWidth, height: notchHeight)
            }
        }
        .offset(x: shakeOffset)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: monitor.state)
        .onChange(of: monitor.state) { _, newState in
            shakeOffset = 0
            if case .error = newState { shakeAnimation() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var floatingLayout: some View {
        ZStack {
            if let content = pillContent {
                HStack(spacing: 6) {
                    pulsingIcon(name: content.icon)
                    Text(content.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background { Capsule().fill(Color.black) }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: monitor.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Pulsing Icon (energy-efficient)

    /// Uses TimelineView at ~2 fps to drive a gentle opacity pulse.
    /// Only active during .processing state. Costs ~2 compositor
    /// frames/sec instead of 120.
    @ViewBuilder
    private func pulsingIcon(name: String) -> some View {
        if isProcessing {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                // Sine wave oscillation: period = 2.2s, range 0.5 – 1.0
                let opacity = 0.75 + 0.25 * sin(seconds * .pi / 1.1)
                Image(systemName: name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(claudeOrange.opacity(opacity))
            }
        } else {
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(claudeOrange)
        }
    }

    private func shakeAnimation() {
        let sequence: [(CGFloat, Double)] = [
            (8, 0.05), (-6, 0.05), (4, 0.05), (-2, 0.05), (0, 0.05)
        ]
        var delay = 0.0
        for (offset, duration) in sequence {
            delay += duration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) {
                    shakeOffset = offset
                }
            }
        }
    }
}
