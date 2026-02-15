// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// AudioManager.swift
// Mic capture (WAV data for Whisper) + audio playback (TTS output).

import AVFoundation
import Foundation

class AudioManager: ObservableObject {

    /// Called with RMS level during capture (for UI metering).
    var onAudioLevel: ((Float) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isCapturing = false

    /// Accumulated raw PCM data from mic (16kHz mono Int16).
    private var capturedData = Data()
    private let captureQueue = DispatchQueue(label: "audio.capture")

    /// Current RMS for VAD.
    @Published var currentRMS: Float = 0

    // MARK: - Audio Session

    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(16000)
        try session.setPreferredIOBufferDuration(0.064)
        try session.setActive(true)
        NSLog("[Audio] Session configured with Bluetooth routing")
    }

    // MARK: - Mic Capture

    func startCapture() throws {
        guard !isCapturing else { return }

        captureQueue.sync { capturedData = Data() }

        // Attach player for TTS playback
        audioEngine.attach(playerNode)
        let playFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false
        )!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playFormat)

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Converter to 16kHz mono Float32
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
        )!
        let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let pcmData: Data
            let rms: Float

            if let converter {
                let ratio = targetFormat.sampleRate / nativeFormat.sampleRate
                let outFrames = UInt32(Double(buffer.frameLength) * ratio)
                guard outFrames > 0,
                      let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }
                var error: NSError?
                var consumed = false
                converter.convert(to: outBuf, error: &error) { _, status in
                    if consumed { status.pointee = .noDataNow; return nil }
                    consumed = true
                    status.pointee = .haveData
                    return buffer
                }
                if error != nil { return }
                pcmData = self.float32ToInt16Data(outBuf)
                rms = self.computeRMS(outBuf)
            } else {
                pcmData = self.float32ToInt16Data(buffer)
                rms = self.computeRMS(buffer)
            }

            DispatchQueue.main.async { self.currentRMS = rms }
            self.onAudioLevel?(rms)

            self.captureQueue.async {
                self.capturedData.append(pcmData)
            }
        }

        try audioEngine.start()
        playerNode.play()
        isCapturing = true
        NSLog("[Audio] Capture started")
    }

    func stopCapture() -> Data {
        guard isCapturing else { return Data() }
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        audioEngine.detach(playerNode)
        isCapturing = false

        var result = Data()
        captureQueue.sync { result = capturedData; capturedData = Data() }
        NSLog("[Audio] Capture stopped, %d bytes", result.count)
        return result
    }

    /// Get current captured data without stopping.
    func currentCapturedData() -> Data {
        var result = Data()
        captureQueue.sync { result = capturedData }
        return result
    }

    /// Reset captured buffer (e.g. after sending to Whisper).
    func resetBuffer() {
        captureQueue.sync { capturedData = Data() }
    }

    // MARK: - Playback (TTS)

    func playAudioData(_ data: Data, sampleRate: Double = 24000) {
        guard isCapturing else {
            // Engine not running, start minimal playback
            return
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )!

        // data is raw PCM bytes — determine frame count based on format
        // If MP3/AAC from TTS, we need a different approach — see TTSService
        let frameCount = UInt32(data.count / 4) // Float32 = 4 bytes
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        guard let floatData = buffer.floatChannelData else { return }
        data.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: Float.self).baseAddress else { return }
            for i in 0..<Int(frameCount) {
                floatData[0][i] = ptr[i]
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stopPlayback() {
        playerNode.stop()
        if isCapturing { playerNode.play() }
    }

    // MARK: - WAV Encoding

    /// Convert raw 16kHz mono Int16 PCM data to a WAV file.
    static func pcmToWAV(_ pcmData: Data, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        wav.append(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })
        wav.append("data".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        wav.append(pcmData)
        return wav
    }

    // MARK: - Helpers

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0, let data = buffer.floatChannelData else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[0][i] * data[0][i] }
        return sqrt(sum / Float(count))
    }

    private func float32ToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
        let count = Int(buffer.frameLength)
        guard count > 0, let data = buffer.floatChannelData else { return Data() }
        var int16s = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let s = max(-1.0, min(1.0, data[0][i]))
            int16s[i] = Int16(s * Float(Int16.max))
        }
        return int16s.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
