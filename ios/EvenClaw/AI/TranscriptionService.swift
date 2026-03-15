// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// TranscriptionService.swift
// Apple Speech framework transcription — no external API needed.

import Foundation
import Speech
import AVFoundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Transcribe")

final class TranscriptionService {

    private var recognizer: SFSpeechRecognizer?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Request speech recognition authorization.
    func prepare() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch status {
        case .authorized:
            log.info("Speech recognition authorized")
        case .denied:
            throw TranscriptionError.permissionDenied
        case .restricted:
            throw TranscriptionError.restricted
        case .notDetermined:
            throw TranscriptionError.permissionDenied
        @unknown default:
            throw TranscriptionError.permissionDenied
        }
    }

    /// Transcribe a recorded audio file to text.
    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                continuation.resume(returning: result)
            }
        }

        let text = result.bestTranscription.formattedString
        log.info("Transcribed: \(text)")
        return text
    }
}

enum TranscriptionError: LocalizedError {
    case permissionDenied
    case restricted
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Speech recognition permission denied"
        case .restricted: return "Speech recognition restricted on this device"
        case .unavailable: return "Speech recognition unavailable"
        case .failed(let msg): return "Transcription failed: \(msg)"
        }
    }
}
