import Foundation

// MARK: - Gemini Tool Call (parsed from server JSON)

struct GeminiFunctionCall {
  let id: String
  let name: String
  let args: [String: Any]
}

struct GeminiToolCall {
  let functionCalls: [GeminiFunctionCall]

  init?(json: [String: Any]) {
    guard let toolCall = json["toolCall"] as? [String: Any],
          let calls = toolCall["functionCalls"] as? [[String: Any]] else {
      return nil
    }
    self.functionCalls = calls.compactMap { call in
      guard let id = call["id"] as? String,
            let name = call["name"] as? String else { return nil }
      let args = call["args"] as? [String: Any] ?? [:]
      return GeminiFunctionCall(id: id, name: name, args: args)
    }
  }
}

// MARK: - Gemini Tool Call Cancellation

struct GeminiToolCallCancellation {
  let ids: [String]

  init?(json: [String: Any]) {
    guard let cancellation = json["toolCallCancellation"] as? [String: Any],
          let ids = cancellation["ids"] as? [String] else {
      return nil
    }
    self.ids = ids
  }
}

// MARK: - Tool Result

enum ToolResult {
  case success(String)
  case failure(String)

  var responseValue: [String: Any] {
    switch self {
    case .success(let result):
      return ["result": result]
    case .failure(let error):
      return ["error": error]
    }
  }
}

// MARK: - Tool Call Status (for UI)

enum ToolCallStatus: Equatable {
  case idle
  case executing(String)
  case completed(String)
  case failed(String, String)
  case cancelled(String)

  var displayText: String {
    switch self {
    case .idle: return ""
    case .executing(let name): return "Running: \(name)..."
    case .completed(let name): return "Done: \(name)"
    case .failed(let name, let err): return "Failed: \(name) - \(err)"
    case .cancelled(let name): return "Cancelled: \(name)"
    }
  }

  var isActive: Bool {
    if case .executing = self { return true }
    return false
  }
}

// MARK: - Tool Declarations (for Gemini setup message)

enum ToolDeclarations {

  static func allDeclarations() -> [[String: Any]] {
    return [delegateTask, sendMessage, webSearch]
  }

  static let delegateTask: [String: Any] = [
    "name": "delegate_task",
    "description": "Execute any task that requires taking action, storing data, or interacting with external services. You have no memory or storage -- this tool is your only way to do anything beyond conversation. Use for: adding to lists, setting reminders, creating notes, research, drafts, scheduling, smart home control, app interactions, or any request that has a real-world effect. When in doubt, use this tool.",
    "parameters": [
      "type": "object",
      "properties": [
        "task": [
          "type": "string",
          "description": "Clear description of what to do, including all relevant details from the conversation"
        ]
      ],
      "required": ["task"]
    ] as [String: Any],
    "behavior": "NON_BLOCKING"
  ]

  static let sendMessage: [String: Any] = [
    "name": "send_message",
    "description": "Send a message to someone via a messaging platform. Supports WhatsApp, Telegram, Slack, Discord, iMessage, Signal, and Teams.",
    "parameters": [
      "type": "object",
      "properties": [
        "to": [
          "type": "string",
          "description": "Recipient name or phone number"
        ],
        "message": [
          "type": "string",
          "description": "Message content to send"
        ],
        "channel": [
          "type": "string",
          "description": "Messaging platform to use (whatsapp, telegram, imessage, slack, discord, signal, teams)"
        ]
      ],
      "required": ["to", "message"]
    ] as [String: Any],
    "behavior": "NON_BLOCKING"
  ]

  static let webSearch: [String: Any] = [
    "name": "web_search",
    "description": "Search the web for current information. Use this when the user asks about recent events, facts you are unsure about, or anything that requires up-to-date data.",
    "parameters": [
      "type": "object",
      "properties": [
        "query": [
          "type": "string",
          "description": "The search query"
        ]
      ],
      "required": ["query"]
    ] as [String: Any]
  ]
}
