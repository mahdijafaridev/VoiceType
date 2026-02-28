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
     Attempts direct paste into launchInitializationDelaythe focused UI element; otherwise copies to clipboard.
     */
    func pasteTextOrCopy(_ text: String) {
        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            print("PasteHelper: empty text, nothing to paste.")
            return
        }

        writeToClipboard(sanitizedText)

        guard AXIsProcessTrusted() else {
            print("PasteHelper: AX not trusted, clipboard fallback.")
            return
        }

        guard let focused = focusedElement() else {
            print("PasteHelper: no focused element, clipboard fallback.")
            return
        }

        let supportsValue = supportsSettableValueAttribute(element: focused)
        if supportsValue {
            let setStatus = setValueUsingCursorAwareInsertion(text: sanitizedText, element: focused)
            if setStatus == .success {
                print("PasteHelper: accessibility set path.")
                return
            }

            print("PasteHelper: AX set value failed (\(axErrorDescription(setStatus))); falling back to Cmd+V.")
            postCommandV()
            return
        }

        print("PasteHelper: element does not support settable AXValue, falling back to Cmd+V.")
        postCommandV()
    }

    /**
     Returns the system-wide focused accessibility element.
     */
    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)

        guard status == .success else {
            print("PasteHelper: failed to get focused element (\(axErrorDescription(status))).")
            return nil
        }
        guard let value else {
            print("PasteHelper: focused element attribute was nil.")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            print("PasteHelper: focused element has unexpected type.")
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /**
     Checks whether an accessibility element supports setting kAXValueAttribute.
     */
    private func supportsSettableValueAttribute(element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if status != .success {
            print("PasteHelper: AXValue settable check failed (\(axErrorDescription(status))).")
            return false
        }

        print("PasteHelper: AXValue settable = \(settable.boolValue).")
        return settable.boolValue
    }

    /**
     Attempts to set kAXValueAttribute using selected range insertion when available.
     */
    private func setValueUsingCursorAwareInsertion(text: String, element: AXUIElement) -> AXError {
        let originalValueResult = currentElementTextValue(element: element)
        switch originalValueResult.status {
        case AXError.success:
            let originalValue = originalValueResult.value
            let selectedRangeResult = selectedTextRange(element: element)
            switch selectedRangeResult.status {
            case AXError.success:
                let range = selectedRangeResult.range
                let inserted = replacing(range: range, in: originalValue, with: text)
                let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, inserted as CFTypeRef)
                if setStatus != AXError.success {
                    print("PasteHelper: setting AXValue with range insertion failed (\(axErrorDescription(setStatus))).")
                    return setStatus
                }

                let caretLocation = NSRange(location: range.location + (text as NSString).length, length: 0)
                let caretStatus = setSelectedTextRange(caretLocation, element: element)
                if caretStatus != AXError.success {
                    print("PasteHelper: set caret after insertion failed (\(axErrorDescription(caretStatus))).")
                }
                return AXError.success
            default:
                print("PasteHelper: selected text range unavailable (\(axErrorDescription(selectedRangeResult.status))); replacing full value.")
                let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (originalValue + text) as CFTypeRef)
                if setStatus != AXError.success {
                    print("PasteHelper: setting AXValue without range failed (\(axErrorDescription(setStatus))).")
                }
                return setStatus
            }
        default:
            print("PasteHelper: could not read current AXValue (\(axErrorDescription(originalValueResult.status))); trying direct set.")
            let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
            if setStatus != AXError.success {
                print("PasteHelper: direct AXValue set failed (\(axErrorDescription(setStatus))).")
            }
            return setStatus
        }
    }

    /**
     Reads the current text value of an accessibility element.
     */
    private func currentElementTextValue(element: AXUIElement) -> (value: String, status: AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard status == AXError.success else {
            return ("", status)
        }

        guard let value else {
            return ("", AXError.success)
        }

        if let text = value as? String {
            return (text, AXError.success)
        }

        if let attributedText = value as? NSAttributedString {
            return (attributedText.string, AXError.success)
        }

        return ("", AXError.success)
    }

    /**
     Reads the selected text range from an accessibility element.
     */
    private func selectedTextRange(element: AXUIElement) -> (range: NSRange, status: AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard status == AXError.success else {
            return (NSRange(location: 0, length: 0), status)
        }
        guard let value else {
            return (NSRange(location: 0, length: 0), AXError.noValue)
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return (NSRange(location: 0, length: 0), AXError.illegalArgument)
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return (NSRange(location: 0, length: 0), AXError.illegalArgument)
        }

        var range = CFRange(location: 0, length: 0)
        let gotRange = AXValueGetValue(axValue, .cfRange, &range)
        guard gotRange else {
            return (NSRange(location: 0, length: 0), AXError.cannotComplete)
        }

        return (NSRange(location: range.location, length: range.length), AXError.success)
    }

    /**
     Sets the selected text range for an accessibility element.
     */
    private func setSelectedTextRange(_ range: NSRange, element: AXUIElement) -> AXError {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else {
            return .cannotComplete
        }

        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
    }

    /**
     Returns a string with the provided range replaced by replacement text.
     */
    private func replacing(range: NSRange, in original: String, with replacement: String) -> String {
        let nsOriginal = original as NSString
        let upperBound = nsOriginal.length
        let location = min(max(0, range.location), upperBound)
        let length = min(max(0, range.length), upperBound - location)
        let safeRange = NSRange(location: location, length: length)
        return nsOriginal.replacingCharacters(in: safeRange, with: replacement)
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
            print("PasteHelper: failed to create Cmd+V events, clipboard fallback only.")
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
        }

        print("PasteHelper: CGEvent Cmd+V fallback path.")
    }

    /**
     Converts AXError values into readable strings for logging.
     */
    private func axErrorDescription(_ error: AXError) -> String {
        switch error {
        case .success:
            return "success"
        case .failure:
            return "failure"
        case .illegalArgument:
            return "illegalArgument"
        case .invalidUIElement:
            return "invalidUIElement"
        case .invalidUIElementObserver:
            return "invalidUIElementObserver"
        case .cannotComplete:
            return "cannotComplete"
        case .attributeUnsupported:
            return "attributeUnsupported"
        case .actionUnsupported:
            return "actionUnsupported"
        case .notificationUnsupported:
            return "notificationUnsupported"
        case .notImplemented:
            return "notImplemented"
        case .notificationAlreadyRegistered:
            return "notificationAlreadyRegistered"
        case .notificationNotRegistered:
            return "notificationNotRegistered"
        case .apiDisabled:
            return "apiDisabled"
        case .noValue:
            return "noValue"
        case .parameterizedAttributeUnsupported:
            return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:
            return "notEnoughPrecision"
        @unknown default:
            return "unknown(\(error.rawValue))"
        }
    }
}
