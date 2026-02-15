// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// WhisperService.swift
// OpenAI Whisper API transcription.

import Foundation

class WhisperService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Transcribe WAV audio data using OpenAI Whisper.
    /// - Parameter audioData: WAV-encoded audio data.
    /// - Returns: Transcribed text.
    func transcribe(audioData: Data) async throws -> String {
        let apiKey = EvenClawConfig.openAIKey
        guard !apiKey.isEmpty else { throw WhisperError.noAPIKey }

        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw WhisperError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // close
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        NSLog("[Whisper] Sending %d bytes for transcription", audioData.count)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WhisperError.networkError("No HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            NSLog("[Whisper] Error HTTP %d: %@", http.statusCode, String(bodyStr.prefix(200)))
            throw WhisperError.apiError(http.statusCode, bodyStr)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw WhisperError.parseError
        }

        NSLog("[Whisper] Transcription: %@", text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "OpenAI API key not configured"
        case .invalidURL: return "Invalid Whisper URL"
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let msg): return "Whisper API error \(code): \(msg)"
        case .parseError: return "Failed to parse Whisper response"
        }
    }
}
