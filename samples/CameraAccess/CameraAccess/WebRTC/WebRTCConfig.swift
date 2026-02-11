import Foundation

enum WebRTCConfig {
  static let signalingServerURL = Secrets.webrtcSignalingURL

  static let iceServers = [
    "stun:stun.l.google.com:19302",
    "stun:stun1.l.google.com:19302"
  ]

  static let maxBitrateBps = 2_500_000  // 2.5 Mbps
  static let maxFramerate = 24

  static var isConfigured: Bool {
    return !signalingServerURL.isEmpty
      && signalingServerURL != "ws://YOUR_MAC_IP:8080"
  }
}
