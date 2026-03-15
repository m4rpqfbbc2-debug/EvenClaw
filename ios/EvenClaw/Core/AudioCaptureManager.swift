// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AudioCaptureManager.swift
// Port of reference/audio.ts — mic capture via AVAudioEngine.
// Mic ON only during LISTENING state. Force-send via double-tap.
// No silence-based auto-send.

import Foundation
import AVFoundation
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "Audio")

final class AudioCaptureManager {

    // MARK: - Callbacks

    var onRecordingComplete: ((URL?) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    // MARK: - State

    private(set) var isRecording = false
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    // MARK: - Public API

    func startRecording() {
        guard !isRecording else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            log.error("Audio session setup failed: \(error.localizedDescription)")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "evenclaw-recording-\(UUID().uuidString).wav"
        let url = tempDir.appendingPathComponent(fileName)
        recordingURL = url

        // Create WAV file with recording format
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        )!

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        } catch {
            log.error("Failed to create audio file: \(error.localizedDescription)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }

            // Convert to mono if needed and write
            if let monoBuffer = self.convertToMono(buffer, outputFormat: recordingFormat) {
                do {
                    try self.audioFile?.write(from: monoBuffer)
                } catch {
                    log.error("Write error: \(error.localizedDescription)")
                }

                // Compute RMS for waveform visualization
                let level = self.computeRMS(monoBuffer)
                self.onAudioLevel?(level)
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isRecording = true
            log.info("Recording started")
        } catch {
            log.error("Engine start failed: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        log.info("Recording stopped")
    }

    /// Force-send: called when user double-taps to send immediately.
    func forceSend() {
        guard isRecording else { return }
        log.info("Force send (double-tap)")
        let url = recordingURL
        stopRecording()
        onRecordingComplete?(url)
    }

    // MARK: - Private

    private func convertToMono(_ buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else { return nil }
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            log.error("Conversion error: \(error.localizedDescription)")
            return nil
        }
        return outputBuffer
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sumSquares: Float = 0
        let data = channelData[0]
        for i in 0..<frameLength {
            let sample = data[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        // Normalize to 0-1 range (rough)
        return min(1.0, rms * 5.0)
    }
}
