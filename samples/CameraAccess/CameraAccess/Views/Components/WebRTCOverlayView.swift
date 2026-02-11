import SwiftUI

struct WebRTCStatusBar: View {
  @ObservedObject var webrtcVM: WebRTCSessionViewModel

  var body: some View {
    HStack(spacing: 8) {
      StatusPill(color: statusColor, text: statusText)

      if !webrtcVM.roomCode.isEmpty {
        RoomCodePill(code: webrtcVM.roomCode)
      }

      if webrtcVM.connectionState == .connected {
        StatusPill(
          color: webrtcVM.isMuted ? .red : .green,
          text: webrtcVM.isMuted ? "Muted" : "Mic On"
        )
      }
    }
  }

  private var statusColor: Color {
    switch webrtcVM.connectionState {
    case .connected: return .green
    case .connecting, .waitingForPeer: return .yellow
    case .error: return .red
    case .disconnected: return .gray
    }
  }

  private var statusText: String {
    switch webrtcVM.connectionState {
    case .connected: return "Live"
    case .connecting: return "Connecting..."
    case .waitingForPeer: return "Waiting..."
    case .error: return "Error"
    case .disconnected: return "Off"
    }
  }
}

struct RoomCodePill: View {
  let code: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "number")
        .font(.system(size: 10))
        .foregroundColor(.white)
      Text(code)
        .font(.system(size: 14, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.6))
    .cornerRadius(16)
  }
}
