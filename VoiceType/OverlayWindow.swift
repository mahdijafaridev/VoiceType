import AppKit
import SwiftUI

/**
 Borderless floating panel used for the recording overlay.
 */
final class OverlayWindow: NSPanel {
    /**
     Creates an always-on-top, non-activating panel.
     */
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/**
 Controller that manages overlay window lifecycle and level updates.
 */
@MainActor
final class OverlayWindowController {
    private let viewModel = WaveformViewModel()
    private lazy var panel: OverlayWindow = makePanel()
    private var toastTask: Task<Void, Never>?

    /**
     Shows and centers the overlay.
     */
    func show() {
        toastTask?.cancel()
        viewModel.toastMessage = nil
        centerOnPreferredScreen()
        panel.orderFrontRegardless()
    }

    /**
     Hides the overlay.
     */
    func hide() {
        toastTask?.cancel()
        viewModel.toastMessage = nil
        panel.orderOut(nil)
    }

    /**
     Pushes a new normalized level into the waveform.
     */
    func update(level: Float) {
        viewModel.level = CGFloat(max(0, min(level, 1)))
    }

    /**
     Shows a short error toast in the overlay.
     */
    func showToast(message: String, duration: TimeInterval = 1.8) {
        toastTask?.cancel()
        centerOnPreferredScreen()
        viewModel.toastMessage = message
        panel.orderFrontRegardless()

        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            viewModel.toastMessage = nil
            panel.orderOut(nil)
        }
    }

    /**
     Creates the panel and embeds the SwiftUI waveform view.
     */
    private func makePanel() -> OverlayWindow {
        let panel = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 132, height: 52))
        panel.contentView = NSHostingView(rootView: WaveformView(model: viewModel))
        return panel
    }

    /**
     Centers the panel on the active screen.
     */
    private func centerOnPreferredScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let fallbackFrame = NSScreen.main?.visibleFrame
        guard
            let frame = Self.selectScreenFrame(
                for: mouseLocation,
                visibleFrames: visibleFrames,
                fallbackVisibleFrame: fallbackFrame
            )
        else {
            return
        }

        let x = frame.midX - panel.frame.width / 2
        let y = frame.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /**
     Selects the visible-frame of the display that contains the reference point.
     */
    static func selectScreenFrame(
        for point: CGPoint,
        visibleFrames: [CGRect],
        fallbackVisibleFrame: CGRect?
    ) -> CGRect? {
        if let matchingFrame = visibleFrames.first(where: { $0.contains(point) }) {
            return matchingFrame
        }

        return fallbackVisibleFrame ?? visibleFrames.first
    }
}
