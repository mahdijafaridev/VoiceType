import AVFoundation
import Accelerate
import Foundation
import Speech

/**
 Handles live audio capture and on-device speech transcription.
 */
@MainActor
final class TranscriptionEngine {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stopContinuation: CheckedContinuation<Result<String, Error>, Never>?
    private var latestTranscript = ""
    private var recognitionError: Error?

    /**
     Callback for normalized microphone level updates in [0, 1].
     */
    var onAudioLevel: ((Float) -> Void)?

    /**
     Starts recording and continuous transcription.
     */
    func startRecording() throws {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            throw NSError(
                domain: "VoiceType",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission is not granted."]
            )
        }

        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "VoiceType", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is unavailable."])
        }

        resolvePendingStopContinuationIfNeeded(
            with: NSError(
                domain: "VoiceType",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Previous recording session was interrupted by a new start request."]
            )
        )
        cleanupRecognitionState()
        latestTranscript = ""
        recognitionError = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
            print("TranscriptionEngine: on-device recognition is unavailable; falling back to non-on-device mode.")
        }
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
            let level = Self.computeAudioLevel(from: buffer)
            Task { @MainActor in
                self.onAudioLevel?(level)
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishStopIfNeeded()
                    }
                }

                if let error {
                    if Self.isBenignRecognitionError(error) {
                    } else {
                        self.recognitionError = error
                    }
                    self.finishStopIfNeeded()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /**
     Stops recording and returns final transcription text.
     */
    func stopRecording() async throws -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // Return quickly when recognition already ended.
        if recognitionTask == nil {
            let text = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }

            if let recognitionError {
                throw recognitionError
            }

            return ""
        }

        let result = await withCheckedContinuation { continuation in
            stopContinuation = continuation

            // Safety timeout: speech tasks can occasionally stall on stop.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.finishStopIfNeeded()
            }
        }

        return try result.get()
    }

    /**
     Cleans up running recognition task and request.
     */
    private func cleanupRecognitionState() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognitionError = nil
    }

    /**
     Ensures any pending stop continuation is resumed before state reset.
     */
    private func resolvePendingStopContinuationIfNeeded(with error: Error) {
        guard let continuation = stopContinuation else { return }
        stopContinuation = nil
        continuation.resume(returning: .failure(error))
    }

    /**
     Completes pending stop continuation once and tears down task resources.
     */
    private func finishStopIfNeeded() {
        guard let continuation = stopContinuation else {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            return
        }

        let text = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopContinuation = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if !text.isEmpty {
            continuation.resume(returning: .success(text))
        } else if let recognitionError {
            continuation.resume(returning: .failure(recognitionError))
        } else {
            continuation.resume(returning: .success(""))
        }
    }

    /**
     Filters recognition errors that are expected during normal stop/cancel flows.
     */
    private static func isBenignRecognitionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        if description.contains("cancel") {
            return true
        }

        // Common cancel-style error codes observed in Speech pipelines.
        return nsError.code == 301 || nsError.code == 203
    }

    /**
     Computes normalized RMS level from audio buffer.
     */
    private static func computeAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        // Map roughly from dB [-50, 0] to [0, 1] for UI usage.
        let avgPower = 20 * log10(max(rms, 0.000_01))
        let normalized = (avgPower + 50) / 50
        return max(0, min(normalized, 1))
    }
}
