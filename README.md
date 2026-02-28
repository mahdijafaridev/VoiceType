# VoiceType

VoiceType is a macOS menu bar app that records while you hold the **Right Command** key, transcribes speech on-device, and pastes text into the focused input.

## Features

- Menu bar utility (no Dock icon)
- Hold **Right Command** to record, release to transcribe
- On-device speech recognition with `SFSpeechRecognizer`
- Floating always-on-top recording overlay with live waveform
- Paste into focused field via Accessibility API
- Clipboard fallback when focused editable field is unavailable
- First-launch permission flow for:
  - Accessibility
  - Microphone
  - Speech Recognition
- Minimal menu options:
  - Hide Menu Bar
  - Launch at Login (enabled by default on first run)

## Requirements

- macOS 13+
- Xcode 15+
- Swift 5+

## Setup

1. Open `VoiceType.xcodeproj` in Xcode.
2. Select the `VoiceType` scheme.
3. Build and run on macOS.

## Permissions

VoiceType needs system permissions to work correctly:

- **Accessibility**: needed to paste into other apps
- **Microphone**: needed for recording
- **Speech Recognition**: needed for transcription

If transcription reports dictation-related failures, enable Dictation in:
`System Settings > Keyboard > Dictation`.

## Usage

1. Launch VoiceType.
2. Click into any text input in any app.
3. Hold **Right Command** to start recording.
4. Release **Right Command** to stop and transcribe.
5. VoiceType pastes text into the focused field (or copies to clipboard fallback).

## Troubleshooting

- Shortcut not working:
  - Confirm Accessibility is enabled for VoiceType.
  - Relaunch app after granting permissions.
- No transcription:
  - Confirm Speech Recognition and Microphone permissions are granted.
  - Check Dictation is enabled in Keyboard settings.
- No paste into target app:
  - Confirm target app has a focused editable field.
  - Clipboard fallback is used when direct insertion is not possible.

## Project Structure

- `VoiceType/VoiceTypeApp.swift`: app entry and delegate wiring
- `VoiceType/AppDelegate.swift`: permissions, key monitor, orchestration
- `VoiceType/TranscriptionEngine.swift`: audio engine + speech pipeline
- `VoiceType/PasteHelper.swift`: Accessibility + clipboard paste logic
- `VoiceType/OverlayWindow.swift`: floating panel + overlay controller
- `VoiceType/WaveformView.swift`: waveform UI driven by audio level

## Notes

- Built as a native SwiftUI/AppKit hybrid for macOS.
- Uses only Apple frameworks (no third-party dependencies).
