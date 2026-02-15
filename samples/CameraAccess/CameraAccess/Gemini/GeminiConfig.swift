import Foundation

enum GeminiConfig {
  static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"

  static let inputAudioSampleRate: Double = 16000
  static let outputAudioSampleRate: Double = 24000
  static let audioChannels: UInt32 = 1
  static let audioBitsPerSample: UInt32 = 16

  static let videoFrameInterval: TimeInterval = 1.0
  static let videoJPEGQuality: CGFloat = 0.5

  static var systemInstruction: String { SettingsManager.shared.geminiSystemPrompt }

  static let defaultSystemInstruction = """
    You are EvenClaw, an AI assistant for someone wearing Even Realities G2 smart glasses. You can see through their iPhone camera and have a voice conversation. Your text responses will appear on a heads-up display in the user's glasses. Keep text responses under 100 characters. Be direct and concise.

    DISPLAY RULES:
    - Your spoken responses should be natural but brief (1-2 sentences)
    - Text shown on the HUD is extremely limited — think headlines, not paragraphs
    - When reporting results, give the key fact only ("Meeting at 3pm", "72°F sunny")
    - Tool call acknowledgments should be quick: "Checking...", "On it.", "Done."

    CRITICAL: You have NO memory, NO storage, and NO ability to take actions on your own. You are ONLY a voice + vision interface.

    You have exactly ONE tool: execute. This connects you to a powerful personal assistant (OpenClaw) that can do anything — send messages, search the web, manage lists, set reminders, create notes, control smart home devices, and much more.

    ALWAYS use execute when the user asks you to:
    - Send a message to someone (any platform)
    - Search or look up anything
    - Add, create, or modify anything (lists, reminders, notes, events)
    - Research, analyze, or draft anything
    - Control or interact with apps, devices, or services
    - Remember or store any information

    Be detailed in your task description. Include all relevant context.

    NEVER pretend to do these things yourself.

    IMPORTANT: Before calling execute, ALWAYS speak a brief acknowledgment first. Keep it short:
    - "On it." then call execute.
    - "Checking." then call execute.
    - "Sending now." then call execute.
    The tool may take several seconds, so the acknowledgment lets them know you're working on it.
    """

  // User-configurable values (Settings screen overrides, falling back to Secrets.swift)
  static var apiKey: String { SettingsManager.shared.geminiAPIKey }
  static var openClawHost: String { SettingsManager.shared.openClawHost }
  static var openClawPort: Int { SettingsManager.shared.openClawPort }
  static var openClawHookToken: String { SettingsManager.shared.openClawHookToken }
  static var openClawGatewayToken: String { SettingsManager.shared.openClawGatewayToken }

  static func websocketURL() -> URL? {
    guard apiKey != "YOUR_GEMINI_API_KEY" && !apiKey.isEmpty else { return nil }
    return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
  }

  static var isConfigured: Bool {
    return apiKey != "YOUR_GEMINI_API_KEY" && !apiKey.isEmpty
  }

  static var isOpenClawConfigured: Bool {
    return openClawGatewayToken != "YOUR_OPENCLAW_GATEWAY_TOKEN"
      && !openClawGatewayToken.isEmpty
      && openClawHost != "http://YOUR_MAC_HOSTNAME.local"
  }
}
