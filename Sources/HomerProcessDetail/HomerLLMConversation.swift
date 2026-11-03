import Foundation
import HomerCore

// An LLM harness command's conversation (`llm-conversation-view.tsx`), from the server's
// translation of its stdout: `GET /api/v1/stream/processes/{id}/llm-events?cmd=N` (Homer 1.27,
// ADR-0070) sends harness-neutral events for Claude Code, Codex and opencode alike, so the app
// no longer parses any one tool's output itself.

/// One `llm.event` frame's event (`LlmEvent` in `types/homer.ts`).
public nonisolated enum HomerLLMEvent: Equatable, Sendable {
	/// The harness started; Claude also sends model-less ones for its hook lines.
	case sessionStart(model: String?)
	case assistantMessage(messageID: String?, text: String)
	case toolCall(Tool)
	case toolResult(id: String, output: String, isError: Bool)
	case turnEnd(TurnEnd)
	/// A retried API error, or a kind this app does not know: neither is shown.
	case other

	public nonisolated struct Tool: Equatable, Sendable {
		public var id: String
		public var name: String
		/// The call's input as indented JSON.
		public var input: String
		/// The input on one line, cut short — the collapsed row's hint.
		public var inputPreview: String
		public var messageID: String?

		public init(id: String, name: String, input: String, inputPreview: String, messageID: String? = nil) {
			self.id = id
			self.name = name
			self.input = input
			self.inputPreview = inputPreview
			self.messageID = messageID
		}
	}

	/// How the harness's run ended, and what it took (`LlmTurnEnd`).
	public nonisolated struct TurnEnd: Equatable, Sendable {
		public nonisolated enum Status: Equatable, Sendable {
			case success
			case failed(reason: String)
			/// A stop the agent may have opted into, e.g. Claude's turn limit: not a failure.
			case stopped(reason: String)
		}

		public nonisolated struct Usage: Equatable, Sendable {
			public var input = 0
			public var output = 0
			public var cacheRead = 0
			public var cacheWrite = 0
			public var reasoning = 0

			public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, reasoning: Int = 0) {
				self.input = input
				self.output = output
				self.cacheRead = cacheRead
				self.cacheWrite = cacheWrite
				self.reasoning = reasoning
			}
		}

		public var status: Status
		public var usage: Usage
		/// Nil when the harness reports tokens only (Codex, opencode).
		public var costUsd: Double?
		public var model: String?
		public var durationMs: Double?
		public var apiDurationMs: Double?
		public var turns: Int?

		public init(
			status: Status,
			usage: Usage = Usage(),
			costUsd: Double? = nil,
			model: String? = nil,
			durationMs: Double? = nil,
			apiDurationMs: Double? = nil,
			turns: Int? = nil
		) {
			self.status = status
			self.usage = usage
			self.costUsd = costUsd
			self.model = model
			self.durationMs = durationMs
			self.apiDurationMs = apiDurationMs
			self.turns = turns
		}
	}

	/// Characters kept of any one text — a tool's input or output can be a whole file, which
	/// the Raw view has in full (the console's `MAX_LLM_EVENT_CHARS`).
	static let maxTextLength = 64 * 1024

	/// The event of an `llm.event` frame's `data`; nil when it is not one.
	init?(frame data: String) {
		guard let frame = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any],
		      let event = frame["event"] as? [String: Any]
		else {
			return nil
		}
		switch event["type"] as? String {
		case "session_start":
			self = .sessionStart(model: event["model"] as? String)
		case "assistant_message":
			self = .assistantMessage(messageID: event["messageId"] as? String, text: Self.clip(event["text"] as? String ?? ""))
		case "tool_call":
			guard let id = event["id"] as? String else {
				return nil
			}
			let input = event["input"] ?? NSNull()
			self = .toolCall(Tool(
				id: id,
				name: event["name"] as? String ?? "tool",
				input: Self.clip(Self.text(input, pretty: true)),
				inputPreview: String(Self.text(input, pretty: false).prefix(80)),
				messageID: event["messageId"] as? String
			))
		case "tool_result":
			guard let id = event["id"] as? String else {
				return nil
			}
			self = .toolResult(
				id: id,
				output: Self.clip(Self.text(event["output"] ?? NSNull(), pretty: true)),
				isError: event["isError"] as? Bool ?? false
			)
		case "turn_end":
			let status = event["status"] as? [String: Any] ?? [:]
			let reason = status["reason"] as? String ?? ""
			let usage = event["usage"] as? [String: Any] ?? [:]
			let turnStatus: TurnEnd.Status = switch status["type"] as? String {
			case "success": .success
			case "stopped": .stopped(reason: reason)
			default: .failed(reason: reason)
			}
			self = .turnEnd(TurnEnd(
				status: turnStatus,
				usage: TurnEnd.Usage(
					input: Self.int(usage["input"]) ?? 0,
					output: Self.int(usage["output"]) ?? 0,
					cacheRead: Self.int(usage["cacheRead"]) ?? 0,
					cacheWrite: Self.int(usage["cacheWrite"]) ?? 0,
					reasoning: Self.int(usage["reasoning"]) ?? 0
				),
				costUsd: Self.double(event["costUsd"]),
				model: event["model"] as? String,
				durationMs: Self.double(event["durationMs"]),
				apiDurationMs: Self.double(event["durationApiMs"]),
				turns: Self.int(event["numTurns"])
			))
		default:
			self = .other
		}
	}

	private static func clip(_ text: String) -> String {
		guard text.count > maxTextLength else {
			return text
		}
		return String(text.prefix(maxTextLength)) + "\n… (\(text.count - maxTextLength) more characters — see Raw)"
	}

	/// A string as it is; anything else as JSON.
	private static func text(_ value: Any, pretty: Bool) -> String {
		if let string = value as? String {
			return string
		}
		guard JSONSerialization.isValidJSONObject(value) else {
			return value is NSNull ? "null" : String(describing: value)
		}
		var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
		if pretty {
			options.insert(.prettyPrinted)
		}
		return (try? JSONSerialization.data(withJSONObject: value, options: options))
			.flatMap { String(data: $0, encoding: .utf8) } ?? ""
	}

	private static func int(_ value: Any?) -> Int? {
		(value as? NSNumber)?.intValue
	}

	private static func double(_ value: Any?) -> Double? {
		(value as? NSNumber)?.doubleValue
	}
}

/// Where an event sits in the command's output: an `llm.event` frame's id,
/// `cmdIndex:attemptIndex:lineOffset:eventIndex`. Sent back as `Last-Event-ID`, it resumes the
/// stream right after that event.
public nonisolated struct HomerLLMCursor: Equatable, Sendable {
	public var id: String
	public var attempt: Int
	public var lineOffset: Int
	public var eventIndex: Int

	public init?(_ id: String?) {
		guard let id else {
			return nil
		}
		let parts = id.split(separator: ":").compactMap { Int($0) }
		guard parts.count == 4 else {
			return nil
		}
		self.id = id
		self.attempt = parts[1]
		self.lineOffset = parts[2]
		self.eventIndex = parts[3]
	}

	/// What to do with an event at this cursor, the last one applied having been at `last`
	/// (`advanceCursor` in the console's `streams.ts`).
	public enum Placement: Equatable, Sendable {
		case next
		/// A new attempt of the command (a retry): its conversation starts over.
		case newAttempt
		/// Already applied — a reconnect replaying from before the resume point.
		case replay
	}

	public func placement(after last: Self?) -> Placement {
		guard let last else {
			return .next
		}
		if attempt != last.attempt {
			return .newAttempt
		}
		if lineOffset < last.lineOffset || (lineOffset == last.lineOffset && eventIndex <= last.eventIndex) {
			return .replay
		}
		return .next
	}
}

/// What the conversation stream sends.
public nonisolated enum HomerLLMStreamEvent: Equatable, Sendable {
	case event(HomerLLMEvent, cursor: HomerLLMCursor?)
	/// The command is done and its output drained.
	case end
}

/// A command's conversation as the sheet shows it: a summary (or, while it runs, a live
/// header), then the assistant's messages and tool calls, each call with its result.
public nonisolated struct HomerLLMConversation: Equatable, Sendable {
	public nonisolated enum Item: Equatable, Sendable, Identifiable {
		case message(id: String, text: String)
		case tool(HomerLLMEvent.Tool, result: Result?)

		public nonisolated struct Result: Equatable, Sendable {
			public var output: String
			public var isError: Bool
		}

		public var id: String {
			switch self {
			case let .message(id, _):
				id
			case let .tool(tool, _):
				"tool-" + tool.id
			}
		}
	}

	/// The first model a `session_start` names — Claude's hook lines come first without one.
	public private(set) var sessionModel: String?
	/// The first `turn_end`: how the run ended.
	public private(set) var outcome: HomerLLMEvent.TurnEnd?
	public private(set) var items: [Item] = []
	/// Distinct assistant messages so far, by message id across messages and tool calls: a
	/// tool-only or thinking-only message still counts once.
	public var turns: Int {
		turnIDs.count
	}

	private var turnIDs: Set<String> = []
	private var toolIndices: [String: Int] = [:]
	/// Results that arrived before their call.
	private var orphanResults: [String: Item.Result] = [:]

	public init() {}

	public init(_ events: [HomerLLMEvent]) {
		for event in events {
			apply(event)
		}
	}

	/// The turn's own model wins over the session's.
	public var model: String? {
		outcome?.model ?? sessionModel
	}

	/// The most recent tool call without a result, which a live view marks as running.
	public var inflightToolID: String? {
		for item in items.reversed() {
			if case let .tool(tool, nil) = item {
				return tool.id
			}
		}
		return nil
	}

	/// Index of the last message: shown in full, every earlier one folded.
	public var lastMessageIndex: Int? {
		items.lastIndex { if case .message = $0 { true } else { false } }
	}

	public mutating func apply(_ event: HomerLLMEvent) {
		switch event {
		case let .sessionStart(model):
			if sessionModel == nil, let model {
				sessionModel = model
			}
		case let .assistantMessage(messageID, text):
			if let messageID {
				turnIDs.insert(messageID)
			}
			// A blank (thinking-only) message shows nothing, but counted as a turn above.
			if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				items.append(.message(id: "message-\(items.count)", text: text))
			}
		case let .toolCall(tool):
			if let messageID = tool.messageID {
				turnIDs.insert(messageID)
			}
			guard toolIndices[tool.id] == nil else {
				return
			}
			toolIndices[tool.id] = items.count
			items.append(.tool(tool, result: orphanResults.removeValue(forKey: tool.id)))
		case let .toolResult(id, output, isError):
			let result = Item.Result(output: output, isError: isError)
			guard let index = toolIndices[id], case let .tool(tool, _) = items[index] else {
				orphanResults[id] = result
				return
			}
			items[index] = .tool(tool, result: result)
		case let .turnEnd(turnEnd):
			if outcome == nil {
				outcome = turnEnd
			}
		case .other:
			break
		}
	}
}
