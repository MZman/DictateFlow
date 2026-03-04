import SwiftUI
import AppKit

@MainActor
final class FloatingOverlayController: NSObject, NSWindowDelegate {
    var onStartPressed: (() -> Void)?
    var onStopPressed: (() -> Void)?
    var onCancelPressed: (() -> Void)?
    var onPositionChanged: ((CGPoint) -> Void)?

    private var panel: NSPanel?
    private let idleSize = NSSize(width: 38, height: 38)
    private let recordingSize = NSSize(width: 228, height: 46)
    private let screenInset: CGFloat = 10

    private var isRecording = false
    private var status: AppStatus = .ready
    private var audioLevel: Double = 0
    private var isApplyingFrameConstraint = false

    private let renderState = OverlayRenderState()

    private var currentPanelSize: NSSize {
        isRecording ? recordingSize : idleSize
    }

    func setVisible(_ isVisible: Bool, preferredOrigin: CGPoint?) {
        if isVisible {
            show(preferredOrigin: preferredOrigin)
        } else {
            panel?.orderOut(nil)
        }
    }

    func update(status: AppStatus, isRecording: Bool, audioLevel: Double = 0) {
        let previousRecordingState = self.isRecording
        self.status = status
        self.isRecording = isRecording
        self.audioLevel = max(0, min(1, audioLevel))

        renderState.status = status
        renderState.isRecording = isRecording
        renderState.audioLevel = self.audioLevel

        panel?.isMovableByWindowBackground = !isRecording

        if previousRecordingState != isRecording {
            resizePanelForCurrentState()
        }
    }

    @discardableResult
    func resetPositionToDefault() -> CGPoint {
        let origin = defaultOrigin()
        ensurePanel(preferredOrigin: origin)
        guard let panel else {
            onPositionChanged?(origin)
            return origin
        }

        let constrained = constrainedFrame(panel.frame, preferredScreen: screenForFrame(panel.frame))
        panel.setFrameOrigin(constrained.origin)
        onPositionChanged?(constrained.origin)
        return constrained.origin
    }

    func hideCompletely() {
        panel?.orderOut(nil)
    }

    private func show(preferredOrigin: CGPoint?) {
        ensurePanel(preferredOrigin: preferredOrigin)
        panel?.orderFrontRegardless()
    }

    private func ensurePanel(preferredOrigin: CGPoint?) {
        if panel == nil {
            let origin = preferredOrigin ?? defaultOrigin()
            let initialFrame = NSRect(origin: origin, size: currentPanelSize)
            let frame = constrainedFrame(
                initialFrame,
                preferredScreen: screenForFrame(initialFrame)
            )

            let newPanel = NSPanel(
                contentRect: frame,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )

            newPanel.isReleasedWhenClosed = false
            newPanel.isFloatingPanel = true
            newPanel.level = .statusBar
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = true
            newPanel.hidesOnDeactivate = false
            newPanel.isMovableByWindowBackground = !isRecording
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            newPanel.delegate = self
            newPanel.ignoresMouseEvents = false

            newPanel.contentView = NSHostingView(
                rootView: OverlayRootView(
                    state: renderState,
                    onStart: { [weak self] in self?.onStartPressed?() },
                    onCancel: { [weak self] in self?.onCancelPressed?() },
                    onStop: { [weak self] in self?.onStopPressed?() }
                )
            )

            panel = newPanel
        } else if let preferredOrigin {
            guard let panel else { return }
            let candidate = NSRect(origin: preferredOrigin, size: panel.frame.size)
            let constrained = constrainedFrame(candidate, preferredScreen: screenForFrame(candidate))
            panel.setFrameOrigin(constrained.origin)
        }
    }

    private func resizePanelForCurrentState() {
        guard let panel else { return }
        let oldFrame = panel.frame
        let targetSize = currentPanelSize
        guard oldFrame.size != targetSize else { return }

        // Behalte die obere rechte Ecke stabil, damit die rechte Aktionsseite sichtbar bleibt.
        let candidate = NSRect(
            x: oldFrame.maxX - targetSize.width,
            y: oldFrame.maxY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        let constrained = constrainedFrame(candidate, preferredScreen: panel.screen ?? screenForFrame(oldFrame))
        panel.setFrame(constrained, display: true, animate: true)
        onPositionChanged?(constrained.origin)
    }

    private func defaultOrigin() -> CGPoint {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = currentPanelSize
        return CGPoint(
            x: visibleFrame.maxX - size.width - 22,
            y: visibleFrame.maxY - size.height - 22
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        guard !isApplyingFrameConstraint else {
            onPositionChanged?(panel.frame.origin)
            return
        }

        let constrained = constrainedFrame(panel.frame, preferredScreen: panel.screen ?? screenForFrame(panel.frame))
        if distanceBetween(panel.frame.origin, constrained.origin) > 0.5 {
            isApplyingFrameConstraint = true
            panel.setFrameOrigin(constrained.origin)
            isApplyingFrameConstraint = false
        }

        onPositionChanged?(panel.frame.origin)
    }

    private func constrainedFrame(_ frame: NSRect, preferredScreen: NSScreen?) -> NSRect {
        let targetScreen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let safeFrame = visibleFrame.insetBy(dx: screenInset, dy: screenInset)

        var result = frame

        if result.width > safeFrame.width {
            result.size.width = safeFrame.width
        }
        if result.height > safeFrame.height {
            result.size.height = safeFrame.height
        }

        if result.minX < safeFrame.minX {
            result.origin.x = safeFrame.minX
        }
        if result.maxX > safeFrame.maxX {
            result.origin.x = safeFrame.maxX - result.width
        }
        if result.minY < safeFrame.minY {
            result.origin.y = safeFrame.minY
        }
        if result.maxY > safeFrame.maxY {
            result.origin.y = safeFrame.maxY - result.height
        }

        return result
    }

    private func screenForFrame(_ frame: NSRect) -> NSScreen? {
        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.visibleFrame.contains(centerPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func distanceBetween(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }
}

@MainActor
private final class OverlayRenderState: ObservableObject {
    @Published var status: AppStatus = .ready
    @Published var isRecording = false
    @Published var audioLevel: Double = 0
}

private struct OverlayRootView: View {
    @ObservedObject var state: OverlayRenderState
    let onStart: () -> Void
    let onCancel: () -> Void
    let onStop: () -> Void

    var body: some View {
        Group {
            if state.isRecording {
                RecordingOverlayView(
                    audioLevel: state.audioLevel,
                    onCancel: onCancel,
                    onStop: onStop
                )
            } else {
                IdleOverlayView(
                    tintColor: state.status.bannerColor,
                    onStart: onStart
                )
            }
        }
    }
}

private struct IdleOverlayView: View {
    let tintColor: Color
    let onStart: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.36))
                .overlay(
                    Circle().stroke(tintColor.opacity(0.44), lineWidth: 0.8)
                )
                .frame(width: 30, height: 30)

            Button(action: onStart) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tintColor)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 38, height: 38)
        .contentShape(Rectangle())
    }
}

private struct RecordingOverlayView: View {
    let audioLevel: Double
    let onCancel: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 26, height: 26)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())

            VoiceSpectrumView(level: audioLevel)
                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)

            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 228, height: 46)
        .background(
            Capsule(style: .continuous)
                .fill(Color.gray.opacity(0.38))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }
}

private struct VoiceSpectrumView: View {
    let level: Double
    private let barCount = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let normalizedLevel = max(0.06, min(1.0, level))
                let viewHeight = max(10, proxy.size.height)

                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let x = Double(index) / Double(max(barCount - 1, 1))
                        let centerBoost = 1.0 - abs((x * 2.0) - 1.0)
                        let phase = (time * 7.2) + (Double(index) * 0.7)
                        let harmonic = (
                            sin(phase) +
                            sin((phase * 1.41) + 0.9) +
                            sin((phase * 2.12) + 1.8)
                        ) / 3.0

                        let activity = normalizedLevel * (0.55 + (0.45 * centerBoost))
                        let baseline = 0.20 + (centerBoost * 0.12)
                        let dynamic = baseline + (max(0, harmonic) * (0.64 * activity)) + (0.20 * activity)
                        let barHeight = max(2.4, CGFloat(dynamic) * viewHeight)
                        let opacity = 0.50 + (0.40 * centerBoost)

                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(opacity))
                            .frame(width: 2, height: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
    }
}
