// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// WaveformView.swift
// Real-time audio waveform visualizer — pixelated 8-bit style bars with phosphor glow.

import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let isActive: Bool
    var barCount: Int = 30
    var barSpacing: CGFloat = 2
    var minBarHeight: CGFloat = 3
    var maxBarHeight: CGFloat = 40
    var barColor: Color = MatrixColor.phosphor

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = sampleLevel(at: index)
                let barHeight = isActive
                    ? minBarHeight + CGFloat(level) * (maxBarHeight - minBarHeight)
                    : minBarHeight

                // Pixelated bar: stack of small squares instead of smooth rectangle
                PixelBar(
                    height: barHeight,
                    maxHeight: maxBarHeight,
                    pixelSize: 3,
                    color: barColor,
                    intensity: isActive ? (0.4 + Double(level) * 0.6) : 0.15
                )
                .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxBarHeight)
    }

    /// Map bar index to a sample from the levels array.
    private func sampleLevel(at barIndex: Int) -> Float {
        guard !levels.isEmpty, isActive else { return 0 }

        let ratio = Float(barIndex) / Float(max(barCount - 1, 1))
        let exactIndex = ratio * Float(levels.count - 1)
        let low = Int(exactIndex)
        let high = min(low + 1, levels.count - 1)
        let frac = exactIndex - Float(low)

        let raw = levels[low] * (1 - frac) + levels[high] * frac
        let scaled = min(raw * 8.0, 1.0)
        return scaled
    }
}

// MARK: - Pixel Bar

/// A single bar rendered as stacked pixel squares for 8-bit aesthetic.
private struct PixelBar: View {
    let height: CGFloat
    let maxHeight: CGFloat
    let pixelSize: CGFloat
    let color: Color
    let intensity: Double

    var pixelCount: Int {
        max(1, Int(height / (pixelSize + 1)))
    }

    var body: some View {
        VStack(spacing: 1) {
            Spacer(minLength: 0)
            ForEach(0..<pixelCount, id: \.self) { i in
                Rectangle()
                    .fill(color.opacity(intensity * (0.6 + Double(i) / Double(max(pixelCount, 1)) * 0.4)))
                    .frame(height: pixelSize)
            }
        }
        .frame(height: maxHeight)
        .shadow(color: color.opacity(intensity * 0.4), radius: 3, x: 0, y: 0)
    }
}

#Preview {
    VStack(spacing: 20) {
        WaveformView(
            levels: (0..<30).map { _ in Float.random(in: 0.01...0.12) },
            isActive: true
        )
        .padding()

        WaveformView(
            levels: [],
            isActive: false
        )
        .padding()
    }
    .background(MatrixColor.terminal)
}
