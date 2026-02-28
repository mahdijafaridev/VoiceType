# VoiceType

VoiceType is a macOS menu bar app that turns speech into text while you hold **Right Command**.
When you release the key, VoiceType transcribes your speech on-device and inserts the text into the active field.

![VoiceType demo](./assets/voicetype-demo.gif)

## Who This Is For

VoiceType is for people who want fast dictation anywhere they can type on macOS, without sending audio to a cloud service.

## What You Get

- Menu bar app (no Dock clutter)
- Press-and-hold recording with **Right Command**
- On-device transcription using Apple Speech
- Floating recording overlay with live waveform feedback
- Direct text insertion into focused inputs
- Clipboard fallback when direct insertion is unavailable
- Simple menu with:
  - `Hide Menu Bar`
  - `Launch at Login`

## Requirements

- macOS 13 or newer
- Xcode 15 or newer (for building/running from source)
- Microphone, Speech Recognition, and Accessibility permissions

## Quick Start (2-3 minutes)

1. Open `VoiceType.xcodeproj` in Xcode.
2. Select the **VoiceType** scheme.
3. Press **Run** (`Cmd + R`).
4. Approve permission prompts when asked.
5. Click into any text field (Notes, Mail, browser, etc.).
6. Hold **Right Command** and speak.
7. Release **Right Command** to transcribe and insert text.

## First-Run Permissions (Important)

VoiceType needs three permissions to work fully:

- **Microphone**: captures your voice
- **Speech Recognition**: performs transcription
- **Accessibility**: inserts text into other apps

If any permission is denied:

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. Enable permissions for `VoiceType` under:
   - Microphone
   - Speech Recognition
   - Accessibility
4. Quit and relaunch VoiceType.

## Daily Use

1. Focus a text field.
2. Hold **Right Command** to record.
3. Speak naturally.
4. Release **Right Command**.
5. Text is inserted automatically.

If direct insertion fails, VoiceType copies text to clipboard so you can paste manually with `Cmd + V`.

## Tips for Better Results

- Speak clearly at a normal pace.
- Reduce background noise.
- Keep microphone input volume healthy (not clipping).
- Pause briefly before releasing **Right Command**.
- Confirm your macOS dictation language matches your speech language.

## Troubleshooting

### Nothing happens when pressing Right Command

- Confirm VoiceType is running in the menu bar.
- Re-check Accessibility permission.
- Try quitting and relaunching VoiceType.

### Transcription fails or returns empty text

- Confirm Microphone + Speech Recognition permissions.
- Enable Dictation in:
  `System Settings > Keyboard > Dictation`
- Test microphone input in another app.

### Text does not appear in target app

- Make sure a writable text field is focused.
- Some secure fields or custom controls block direct insertion.
- Use clipboard fallback (`Cmd + V`) when needed.

## Privacy

- Transcription is performed on-device via Apple frameworks.
- VoiceType does not include third-party analytics or SDKs.

## Build From Source

1. Clone this repository.
2. Open `VoiceType.xcodeproj`.
3. Build and run with Xcode.

## Project Structure

- `VoiceType/VoiceTypeApp.swift`: app entry and delegate wiring
- `VoiceType/AppDelegate.swift`: permissions, key monitor, orchestration
- `VoiceType/TranscriptionEngine.swift`: audio engine + speech pipeline
- `VoiceType/PasteHelper.swift`: Accessibility + clipboard insertion logic
- `VoiceType/OverlayWindow.swift`: floating overlay window
- `VoiceType/WaveformView.swift`: live waveform visualization

## FAQ

### Does VoiceType require internet?

VoiceType is designed for on-device transcription through Apple APIs. Availability can vary by macOS language/support settings.

### Can I change the shortcut key?

Not yet. Current trigger is **Right Command**.

### Can I hide it from menu bar?

Yes. Use `Hide Menu Bar` in the app menu.
