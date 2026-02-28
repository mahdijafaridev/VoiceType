import AppKit
import ApplicationServices
import Foundation

/**
 Pastes transcribed text into the focused input field when possible.
 Falls back to clipboard plus Cmd+V when direct accessibility insertion is unavailable.
 */
@MainActor
final class PasteHelper {
    /**
     Attempts direct paste into the focused UI element; otherwise copies to clipboard.
     */
    func pasteTextOrCopy(_ text: String) {
        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            return
        }

        writeToClipboard(sanitizedText)

        guard let focused = focusedElement(), isLikelyEditable(element: focused) else {
            postCommandV()
            return
        }

        if insertSelectedText(sanitizedText, into: focused) {
            return
        }

        postCommandV()
    }

    /**
     Returns the system-wide focused accessibility element.
     */
    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)

        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /**
     Checks if an accessibility element likely supports text edits.
     */
    private func isLikelyEditable(element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let settableValue = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if settableValue == .success, settable.boolValue {
            return true
        }

        let settableSelected = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        return settableSelected == .success && settable.boolValue
    }

    /**
     Attempts inserting text through accessibility APIs, preserving caret position.
     */
    private func insertSelectedText(_ text: String, into element: AXUIElement) -> Bool {
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return status == .success
    }

    /**
     Writes text to the system pasteboard.
     */
    private func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /**
     Synthesizes Cmd+V to paste clipboard into the focused app.
     */
    private func postCommandV() {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return
        }

        down.flags = .maskCommand
        up.flags = .maskCommand

        // Post through both HID and annotated taps for broader compatibility.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        if let frontmostPID {
            down.postToPid(frontmostPID)
            up.postToPid(frontmostPID)
        } else {
        }
    }
}
