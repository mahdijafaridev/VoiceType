import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import ServiceManagement
import Speech

/**
 Background event-tap monitor dedicated to right-Command hold detection.
 */
private final class RightCommandKeyMonitor {
    private static let rightCommandKeyCode: Int64 = 54

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isRightCommandPressed = false

    /**
     Called when right-Command transitions between pressed and released.
     */
    var onPressStateChanged: ((Bool) -> Void)?
    var isUsingEventTap: Bool { eventTap != nil }

    /**
     Starts the monitor on its own run-loop thread.
     */
    func start() -> Bool {
        if eventTap != nil || globalFlagsMonitor != nil || localFlagsMonitor != nil {
            return true
        }

        guard let tap = createEventTap() else {
            return startNSEventFallbackMonitors()
        }

        return startEventTapThread(with: tap)
    }

    /**
     Promotes fallback NSEvent monitors to CGEventTap when permissions become available.
     */
    func promoteToEventTapIfPossible() -> Bool {
        guard eventTap == nil else { return true }
        guard let tap = createEventTap() else { return false }

        stopFallbackMonitors()
        return startEventTapThread(with: tap)
    }

    /**
     Starts fallback NSEvent monitors when low-level event tap is unavailable.
     */
    private func startNSEventFallbackMonitors() -> Bool {

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event: event)
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event: event)
            return event
        }

        let started = (globalFlagsMonitor != nil) || (localFlagsMonitor != nil)
        return started
    }

    /**
     Creates low-level event tap if the process is currently allowed to observe session events.
     */
    private func createEventTap() -> CFMachPort? {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<RightCommandKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleEvent(proxy: proxy, type: type, event: event)
        }

        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /**
     Starts the event tap processing loop on a dedicated background thread.
     */
    private func startEventTapThread(with tap: CFMachPort) -> Bool {
        eventTap = tap
        let ready = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self, let tap = self.eventTap else {
                ready.signal()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let currentRunLoop = CFRunLoopGetCurrent()

            self.runLoopSource = source
            self.runLoop = currentRunLoop

            if let source {
                CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            }

            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }

        thread.name = "dev.mahdijafari.voicetype.right-command-monitor"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()

        _ = ready.wait(timeout: .now() + 1)
        return true
    }

    /**
     Removes NSEvent fallback monitors if present.
     */
    private func stopFallbackMonitors() {
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
    }

    /**
     Stops the monitor and tears down thread-owned run-loop resources.
     */
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
            CFRunLoopStop(runLoop)
        }

        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        thread = nil
        stopFallbackMonitors()
        isRightCommandPressed = false
    }

    /**
     Event-tap callback that emits right-command state transitions.
     */
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.rightCommandKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let commandPressed = event.flags.contains(.maskCommand)
        guard commandPressed != isRightCommandPressed else {
            return Unmanaged.passUnretained(event)
        }

        isRightCommandPressed = commandPressed
        onPressStateChanged?(commandPressed)
        return Unmanaged.passUnretained(event)
    }

    /**
     Handles `flagsChanged` from NSEvent monitor fallback.
     */
    private func handleFlagsChanged(event: NSEvent) {
        guard Int64(event.keyCode) == Self.rightCommandKeyCode else { return }

        let commandPressed = event.modifierFlags.contains(.command)
        guard commandPressed != isRightCommandPressed else { return }

        isRightCommandPressed = commandPressed
        onPressStateChanged?(commandPressed)
    }
}

/**
 App delegate for status item setup, permissions, key monitoring, and flow coordination.
 */
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let transcriptionEngine = TranscriptionEngine()
    private let pasteHelper = PasteHelper()
    private let overlayController = OverlayWindowController()
    private let rightCommandMonitor = RightCommandKeyMonitor()

    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var isMenuBarIconVisible = true
    private var isRightCommandPressed = false
    private var isRecording = false
    private var isShowingSpeechSettingsPrompt = false
    private var keyMonitorRecoveryTimer: Timer?
    private var previousApp: NSRunningApplication?
    private var workspaceActivationObserver: NSObjectProtocol?

    private let accessibilityPromptedKey = "didPromptAccessibility"
    private let launchAtLoginConfiguredKey = "didConfigureLaunchAtLoginDefault"
    private let launchInitializationDelay: TimeInterval = 2.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startTrackingPreviouslyFocusedApp()
        setupStatusItem()
        configureLaunchAtLoginDefault()
        wireLevelUpdates()
        startAppServicesAfterLaunchDelay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTrackingPreviouslyFocusedApp()
        keyMonitorRecoveryTimer?.invalidate()
        keyMonitorRecoveryTimer = nil
        stopGlobalKeyMonitor()
    }

    /**
     Tracks the last active app outside VoiceType for targeted fallback paste events.
     */
    private func startTrackingPreviouslyFocusedApp() {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmostApp
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier != Bundle.main.bundleIdentifier
            else {
                return
            }

            self.previousApp = app
        }
    }

    /**
     Removes workspace app-activation tracking observer.
     */
    private func stopTrackingPreviouslyFocusedApp() {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
    }

    /**
     Defers startup-sensitive services to avoid interrupting user activity immediately after launch.
     */
    private func startAppServicesAfterLaunchDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + launchInitializationDelay) { [weak self] in
            guard let self else { return }
            self.requestPermissionsIfNeeded()
            self.startGlobalKeyMonitor()
        }
    }

    /**
     Connects microphone level events to the overlay view model.
     */
    private func wireLevelUpdates() {
        transcriptionEngine.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.overlayController.update(level: level)
            }
        }

        rightCommandMonitor.onPressStateChanged = { [weak self] isPressed in
            Task { @MainActor in
                self?.handleRightCommandStateChange(isPressed: isPressed)
            }
        }
    }

    /**
     Creates menu bar status item and basic menu actions.
     */
    private func setupStatusItem() {
        guard isMenuBarIconVisible else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let iconImage = NSImage(named: "MenuBarIcon") {
            iconImage.size = NSSize(width: 18, height: 18)
            item.button?.image = iconImage
        } else {
            item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceType")
        }
        item.button?.toolTip = "Hold Right Command to record"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hide Menu Bar", action: #selector(hideMenuBarIcon), keyEquivalent: "h"))
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VoiceType", action: #selector(quitVoiceType), keyEquivalent: "q"))
        self.launchAtLoginItem = launchAtLoginItem

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    /**
     Hides the status icon for a cleaner menu bar.
     */
    @objc
    private func hideMenuBarIcon() {
        guard isMenuBarIconVisible else { return }
        isMenuBarIconVisible = false

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        statusItem = nil
    }

    /**
     Terminates the application from the menu bar.
     */
    @objc
    private func quitVoiceType() {
        NSApp.terminate(nil)
    }

    /**
     Enables launch-at-login by default on first run.
     */
    private func configureLaunchAtLoginDefault() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: launchAtLoginConfiguredKey) else { return }
        defaults.set(true, forKey: launchAtLoginConfiguredKey)

        setLaunchAtLogin(enabled: true)
        launchAtLoginItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    /**
     Toggles launch-at-login registration.
     */
    @objc
    private func toggleLaunchAtLogin() {
        let shouldEnable = !isLaunchAtLoginEnabled()
        setLaunchAtLogin(enabled: shouldEnable)
        launchAtLoginItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    /**
     Returns launch-at-login status for the current app.
     */
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        return false
    }

    /**
     Registers or unregisters launch-at-login.
     */
    private func setLaunchAtLogin(enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            overlayController.showToast(message: "Couldn't update launch at login.")
        }
    }

    /**
     Requests first-launch permissions for Accessibility, microphone, and speech.
     */
    private func requestPermissionsIfNeeded() {
        requestAccessibilityPermissionIfNeeded()

        Task {
            await requestSpeechPermissionIfNeeded()
            await requestMicrophonePermissionIfNeeded()
        }
    }

    /**
     Displays explanation and triggers system Accessibility consent prompt when needed.
     */
    private func requestAccessibilityPermissionIfNeeded() {
        let trusted = AXIsProcessTrusted()
        if trusted { return }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: accessibilityPromptedKey) {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Needed"
            alert.informativeText = "VoiceType needs Accessibility access to paste transcribed text into the currently focused input field."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Continue")
            alert.runModal()
            defaults.set(true, forKey: accessibilityPromptedKey)
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /**
     Requests speech recognition authorization once.
     */
    private func requestSpeechPermissionIfNeeded() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return }

        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume(returning: ())
            }
        }
    }

    /**
     Requests microphone authorization once.
     */
    private func requestMicrophonePermissionIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .notDetermined else { return }

        _ = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                continuation.resume(returning: ())
            }
        }
    }

    /**
     Starts a CGEvent tap for global modifier key tracking.
     */
    private func startGlobalKeyMonitor() {
        let monitorStarted = rightCommandMonitor.start()
        if !monitorStarted {
            overlayController.showToast(message: "Global keyboard monitoring is unavailable.")
        }
        ensureEventTapRecoveryLoop()
    }

    /**
     Stops and cleans up global event tap.
     */
    private func stopGlobalKeyMonitor() {
        keyMonitorRecoveryTimer?.invalidate()
        keyMonitorRecoveryTimer = nil
        rightCommandMonitor.stop()
    }

    /**
     Periodically retries event-tap promotion in case permissions are granted after launch.
     */
    private func ensureEventTapRecoveryLoop() {
        if rightCommandMonitor.isUsingEventTap {
            keyMonitorRecoveryTimer?.invalidate()
            keyMonitorRecoveryTimer = nil
            return
        }

        if keyMonitorRecoveryTimer != nil { return }
        keyMonitorRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard AXIsProcessTrusted() else { return }
                if self.rightCommandMonitor.promoteToEventTapIfPossible() {
                    self.keyMonitorRecoveryTimer?.invalidate()
                    self.keyMonitorRecoveryTimer = nil
                }
            }
        }
    }

    /**
     Handles right-command transitions emitted by the background key monitor.
     */
    private func handleRightCommandStateChange(isPressed: Bool) {

        if isPressed, !isRightCommandPressed {
            isRightCommandPressed = true
            beginRecordingIfPossible()
        } else if !isPressed, isRightCommandPressed {
            isRightCommandPressed = false
            endRecordingAndProcessText()
        }
    }

    /**
     Starts transcription and displays recording overlay.
     */
    private func beginRecordingIfPossible() {
        guard !isRecording else { return }
        isRecording = true

        do {
            overlayController.show()
            try transcriptionEngine.startRecording()
        } catch {
            isRecording = false
            handleSpeechError(error)
        }
    }

    /**
     Stops recording, transcribes, and inserts resulting text.
     */
    private func endRecordingAndProcessText() {
        guard isRecording else { return }
        isRecording = false
        overlayController.hide()

        Task {
            do {
                let text = try await transcriptionEngine.stopRecording()
                let trusted = AXIsProcessTrusted()
                print("AppDelegate: AXIsProcessTrusted() = \(trusted)")
                pasteHelper.previousApp = previousApp
                pasteHelper.pasteTextOrCopy(text)
            } catch {
                handleSpeechError(error)
            }
        }
    }

    /**
     Maps low-level speech errors into user-facing guidance.
     */
    private func userFacingSpeechErrorMessage(from error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("siri and dictation are disabled") {
            return "Enable Dictation in System Settings > Keyboard > Dictation."
        }

        return message
    }

    /**
     Presents user-facing guidance for speech failures and links to relevant settings.
     */
    private func handleSpeechError(_ error: Error) {
        let lowercased = error.localizedDescription.lowercased()
        if lowercased.contains("no speech detected") {
            return
        }

        if lowercased.contains("siri and dictation are disabled") {
            overlayController.showToast(message: "Enable Dictation in Keyboard settings.")
            promptToOpenSettings(
                title: "Dictation Is Disabled",
                info: "VoiceType uses Apple Speech Recognition. Enable Dictation in Keyboard settings, then try again.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
            )
            return
        }

        if lowercased.contains("permission is not granted") {
            overlayController.showToast(message: "Enable Speech Recognition permission.")
            promptToOpenSettings(
                title: "Speech Permission Needed",
                info: "Allow Speech Recognition for VoiceType in Privacy & Security settings.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            )
        }
    }

    /**
     Shows a single settings prompt and optionally opens a specific settings pane.
     */
    private func promptToOpenSettings(title: String, info: String, settingsURL: URL?) {
        guard !isShowingSpeechSettingsPrompt else { return }
        isShowingSpeechSettingsPrompt = true

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let settingsURL {
            let opened = NSWorkspace.shared.open(settingsURL)
            if !opened {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"), configuration: NSWorkspace.OpenConfiguration())
            }
        }

        isShowingSpeechSettingsPrompt = false
    }

}
