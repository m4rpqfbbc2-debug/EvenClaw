// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// WaveformView.swift
// 8-bit pixel-style waveform bars during recording.

import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let barCount = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                WaveformBar(level: level)
            }
        }
        .frame(height: 40)
    }
}

private struct WaveformBar: View {
    let level: CGFloat
    private let maxBlocks = 8

    var body: some View {
        VStack(spacing: 1) {
            ForEach((0..<maxBlocks).reversed(), id: \.self) { block in
                let threshold = CGFloat(block) / CGFloat(maxBlocks)
                Rectangle()
                    .fill(level > threshold ? MatrixTheme.primary : MatrixTheme.dim.opacity(0.3))
                    .frame(width: 6, height: 4)
            }
        }
    }
}

#Preview {
    WaveformView(levels: [0.2, 0.5, 0.8, 1.0, 0.7, 0.3, 0.6, 0.4])
        .padding()
        .background(MatrixTheme.background)
}
