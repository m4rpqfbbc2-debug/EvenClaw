// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// TTSService.swift
// OpenAI TTS API — speaks responses through the device (routes to G2 via Bluetooth).

import AVFoundation
import Foundation

class TTSService {

    private let session: URLSession
    private var audioPlayer: AVAudioPlayer?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Speak text using OpenAI TTS. Audio plays through the current audio route
    /// (including Bluetooth G2 speakers if connected).
    func speak(_ text: String) async throws {
        guard EvenClawConfig.ttsEnabled else { return }
        let apiKey = EvenClawConfig.openAIKey
        guard !apiKey.isEmpty else { return }

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1",
            "voice": EvenClawConfig.ttsVoice,
            "input": text,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NSLog("[TTS] Speaking %d chars with voice=%@", text.count, EvenClawConfig.ttsVoice)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[TTS] Error HTTP %d", code)
            return
        }

        NSLog("[TTS] Received %d bytes of audio", data.count)

        // Play MP3 data through AVAudioPlayer (routes to Bluetooth if connected)
        await MainActor.run {
            do {
                self.audioPlayer = try AVAudioPlayer(data: data)
                self.audioPlayer?.play()
            } catch {
                NSLog("[TTS] Playback error: %@", error.localizedDescription)
            }
        }
    }

    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
