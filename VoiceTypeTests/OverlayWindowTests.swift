import CoreGraphics
import Testing
@testable import VoiceType

/**
 Tests for multi-display overlay placement selection.
 */
@MainActor
struct OverlayWindowTests {
    @Test("selectScreenFrame picks the display containing the pointer")
    func selectsContainingDisplay() {
        let leftDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightDisplay = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let pointOnRight = CGPoint(x: 2300, y: 700)

        let selected = OverlayWindowController.selectScreenFrame(
            for: pointOnRight,
            visibleFrames: [leftDisplay, rightDisplay],
            fallbackVisibleFrame: leftDisplay
        )

        #expect(selected == rightDisplay)
    }

    @Test("selectScreenFrame falls back when point is outside every display")
    func fallsBackWhenPointOutside() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let outsidePoint = CGPoint(x: -500, y: -500)

        let selected = OverlayWindowController.selectScreenFrame(
            for: outsidePoint,
            visibleFrames: [display],
            fallbackVisibleFrame: display
        )

        #expect(selected == display)
    }
}
