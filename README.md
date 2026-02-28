# VoiceType

VoiceType is a Mac menu bar app that lets you talk instead of type.

Hold **Right Command** to record your voice. Release it, and your words are inserted into the text box you are using.

![VoiceType demo](./assets/voicetype-demo.gif)

## What VoiceType Does

- Lives in your menu bar
- Records while you hold **Right Command**
- Turns speech into text
- Inserts text into the app you are currently typing in
- Uses clipboard paste as backup when direct insert is not possible

## Before You Start

VoiceType needs these permissions:

- **Microphone**
- **Speech Recognition**
- **Accessibility**

Without these, it will not work correctly.

## Install

1. Open VoiceType.
2. If macOS asks for permissions, click **Allow**.
3. If you do not see prompts, follow the permission steps below.

## Set Permissions Manually (If Needed)

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. Turn on VoiceType in:
   - **Microphone**
   - **Speech Recognition**
   - **Accessibility**
4. Quit and reopen VoiceType.

## How To Use

1. Click inside any text field (Notes, Mail, browser, chat apps, etc.).
2. Hold **Right Command** and speak.
3. Release **Right Command**.
4. Your text appears where the cursor is.

If direct insertion is blocked by an app, VoiceType copies the text so you can paste with `Cmd + V`.

## Tips for Better Dictation

- Speak clearly at a normal pace.
- Use a quiet room when possible.
- Keep your microphone close enough to your voice.
- Wait a brief moment after speaking, then release **Right Command**.

## Troubleshooting

### Nothing happens when I hold Right Command

- Make sure VoiceType is running (menu bar icon visible).
- Re-check **Accessibility** permission.
- Quit and reopen VoiceType.

### It hears me but no text appears

- Re-check **Microphone** and **Speech Recognition** permissions.
- Make sure you clicked into a text field first.
- Try another app (for example, Notes) to test.

### It does not type into one specific app

Some apps or secure input fields block direct text insertion.
Use the copied text and paste manually with `Cmd + V`.

### Speech recognition is failing

Turn on Dictation in:
`System Settings > Keyboard > Dictation`

## Privacy

- VoiceType is designed to transcribe using Apple system features.
- No third-party analytics or ad SDKs are included.

## Quick FAQ

### Do I need to keep VoiceType open?

Yes. It runs from the menu bar.

### Can I change the shortcut key?

Not currently. The shortcut is **Right Command**.

### Can I hide the menu bar icon?

Yes. Use **Hide Menu Bar** in VoiceType’s menu.
