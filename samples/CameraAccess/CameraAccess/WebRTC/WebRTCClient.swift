import Foundation
import WebRTC

protocol WebRTCClientDelegate: AnyObject {
  func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
  func webRTCClient(_ client: WebRTCClient, didGenerateCandidate candidate: RTCIceCandidate)
}

/// Manages RTCPeerConnection, video/audio tracks, and SDP negotiation.
/// Video uses a custom capturer (fed by DAT SDK frames). Audio uses WebRTC's native engine.
class WebRTCClient: NSObject {
  weak var delegate: WebRTCClientDelegate?

  private let factory: RTCPeerConnectionFactory
  private var peerConnection: RTCPeerConnection?
  private var videoSource: RTCVideoSource!
  private var videoCapturer: CustomVideoCapturer!
  private var localVideoTrack: RTCVideoTrack?
  private var localAudioTrack: RTCAudioTrack?

  override init() {
    RTCInitializeSSL()
    let encoderFactory = RTCDefaultVideoEncoderFactory()
    let decoderFactory = RTCDefaultVideoDecoderFactory()
    self.factory = RTCPeerConnectionFactory(
      encoderFactory: encoderFactory,
      decoderFactory: decoderFactory
    )
    super.init()
  }

  func setup() {
    let config = RTCConfiguration()
    config.iceServers = [
      RTCIceServer(urlStrings: WebRTCConfig.iceServers)
    ]
    config.sdpSemantics = .unifiedPlan
    config.continualGatheringPolicy = .gatherContinually

    let constraints = RTCMediaConstraints(
      mandatoryConstraints: nil,
      optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
    )

    peerConnection = factory.peerConnection(
      with: config, constraints: constraints, delegate: self
    )

    createMediaTracks()
  }

  private func createMediaTracks() {
    // Video track — custom source fed by DAT SDK frames
    videoSource = factory.videoSource()
    videoCapturer = CustomVideoCapturer(delegate: videoSource)
    localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
    localVideoTrack?.isEnabled = true
    peerConnection?.add(localVideoTrack!, streamIds: ["stream0"])

    // Audio track — WebRTC native audio (handles mic capture, AEC, playback)
    let audioConstraints = RTCMediaConstraints(
      mandatoryConstraints: nil, optionalConstraints: nil
    )
    let audioSource = factory.audioSource(with: audioConstraints)
    localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
    localAudioTrack?.isEnabled = true
    peerConnection?.add(localAudioTrack!, streamIds: ["stream0"])
  }

  /// Called by ViewModel to push video frames from DAT SDK / iPhone camera.
  func pushVideoFrame(_ image: UIImage) {
    videoCapturer?.pushFrame(image)
  }

  // MARK: - SDP Negotiation

  func createOffer(completion: @escaping (RTCSessionDescription) -> Void) {
    let constraints = RTCMediaConstraints(
      mandatoryConstraints: [
        "OfferToReceiveAudio": "true",
        "OfferToReceiveVideo": "false",
      ],
      optionalConstraints: nil
    )
    peerConnection?.offer(for: constraints) { [weak self] sdp, error in
      guard let sdp else {
        NSLog("[WebRTC] Failed to create offer: %@", error?.localizedDescription ?? "unknown")
        return
      }
      self?.peerConnection?.setLocalDescription(sdp) { error in
        if let error {
          NSLog(
            "[WebRTC] Failed to set local description: %@", error.localizedDescription)
        } else {
          completion(sdp)
        }
      }
    }
  }

  func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
    peerConnection?.setRemoteDescription(remoteSdp, completionHandler: completion)
  }

  func set(remoteCandidate: RTCIceCandidate, completion: @escaping (Error?) -> Void) {
    peerConnection?.add(remoteCandidate, completionHandler: completion)
  }

  func muteAudio(_ mute: Bool) {
    localAudioTrack?.isEnabled = !mute
  }

  func close() {
    localVideoTrack?.isEnabled = false
    localAudioTrack?.isEnabled = false
    peerConnection?.close()
    peerConnection = nil
    NSLog("[WebRTC] Peer connection closed")
  }

  deinit {
    RTCCleanupSSL()
  }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {
  func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
  ) {
    NSLog("[WebRTC] Signaling state: %d", stateChanged.rawValue)
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
  ) {
    NSLog("[WebRTC] ICE connection state: %d", newState.rawValue)
    delegate?.webRTCClient(self, didChangeConnectionState: newState)
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
  ) {
    NSLog("[WebRTC] ICE gathering state: %d", newState.rawValue)
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate
  ) {
    delegate?.webRTCClient(self, didGenerateCandidate: candidate)
  }

  func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    NSLog("[WebRTC] Remote stream added with %d audio tracks", stream.audioTracks.count)
  }

  func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
  }

  func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    NSLog("[WebRTC] Negotiation needed")
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel
  ) {}
}
