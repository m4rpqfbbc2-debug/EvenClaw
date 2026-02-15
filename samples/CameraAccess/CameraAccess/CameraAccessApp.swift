// EvenClaw - XGX.ai
// Copyright 2026 XGX.ai. All rights reserved.
//
// Main app: BLE packet sniffer for Even G2 Conversate reverse engineering

import SwiftUI

@main
struct EvenClawApp: App {
    @StateObject private var sniffer = G2Sniffer()

    var body: some Scene {
        WindowGroup {
            SnifferView(sniffer: sniffer)
        }
    }
}

struct SnifferView: View {
    @ObservedObject var sniffer: G2Sniffer
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("EvenClaw")
                    .font(.headline.bold())
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gear").font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Status bar
            HStack(spacing: 16) {
                StatusDot(label: "BLE", isConnected: sniffer.bleConnected)
                StatusDot(label: "Auth", isConnected: sniffer.authenticated)
                StatusDot(label: "OpenClaw", isConnected: sniffer.openClawConnected)
                Spacer()
                Text("\(sniffer.packetCount) pkts")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Conversate live text (if any)
            if !sniffer.conversateText.isEmpty {
                VStack(spacing: 4) {
                    Text(sniffer.conversateText)
                        .font(.body)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if sniffer.conversateFinal {
                        Text("✅ FINAL")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
            }

            // Status message
            if !sniffer.statusMessage.isEmpty {
                Text(sniffer.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            // Packet log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sniffer.packetLog) { entry in
                            PacketRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: sniffer.packetLog.count) { _ in
                    if let last = sniffer.packetLog.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Controls
            HStack(spacing: 12) {
                Button(sniffer.bleConnected ? "Disconnect" : "Connect") {
                    if sniffer.bleConnected {
                        sniffer.disconnect()
                    } else {
                        Task { await sniffer.connectAndAuth() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(sniffer.bleConnected ? .red : .blue)

                Button("Clear") {
                    sniffer.clearLog()
                }
                .buttonStyle(.bordered)

                Button("Copy Log") {
                    UIPasteboard.general.string = sniffer.exportLog()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await sniffer.connectAndAuth()
        }
    }
}

struct PacketRow: View {
    let entry: PacketLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(entry.timestamp)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(entry.direction)
                    .font(.caption2.bold())
                    .foregroundStyle(entry.direction == "RX" ? .cyan : .orange)
                Text(entry.serviceLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(entry.isConversate ? .green : .white)
                Spacer()
                Text("\(entry.size)B")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(entry.hexDump)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.gray)
                .lineLimit(2)
            if let parsed = entry.parsedContent {
                Text(parsed)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusDot: View {
    let label: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isConnected ? .green : .gray)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
