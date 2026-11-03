import Foundation

/// How an LLM harness command's spend was priced (`LlmAccounting` in Homer's
/// `models/LlmAccounting.kt`, ADR-0061): sent on each finished `claude`, `codex` or `opencode`
/// command; nil for any other command, and from a server that predates it.
public nonisolated struct HomerLLMAccounting: Equatable, Sendable, Decodable {
	/// Tokens summed over every turn end of the attempt that counted.
	public nonisolated struct Usage: Equatable, Sendable, Decodable {
		public var input: Int
		public var output: Int
		public var cacheRead: Int
		public var cacheWrite: Int
		public var reasoning: Int

		public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, reasoning: Int = 0) {
			self.input = input
			self.output = output
			self.cacheRead = cacheRead
			self.cacheWrite = cacheWrite
			self.reasoning = reasoning
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
			output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
			cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
			cacheWrite = try container.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
			reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
		}

		private enum CodingKeys: String, CodingKey {
			case input, output, cacheRead, cacheWrite, reasoning
		}

		/// `in 1,200 / out 340 / cache↑ 9,000 / reasoning 12`, the counts that are not zero past
		/// input and output — the conversation's summary writes its tokens the same way.
		public var text: String {
			var text = "in \(input.formatted()) / out \(output.formatted())"
			if cacheRead > 0 {
				text += " / cache↑ \(cacheRead.formatted())"
			}
			if cacheWrite > 0 {
				text += " / cache+ \(cacheWrite.formatted())"
			}
			if reasoning > 0 {
				text += " / reasoning \(reasoning.formatted())"
			}
			return text
		}
	}

	/// The harness's session; nil when its output named none.
	public var sessionId: String?
	/// What the command was charged — 0 when `source` is `none`.
	public var costUsd: Double
	/// Which price produced `costUsd`: `cli`, `session` or `none` (`HomerCostSource`).
	public var source: String
	/// Set when the figure is degraded: why a configured higher price failed (`cli`), or that a
	/// session figure was charged before the endpoint had every call (`session`).
	public var fallbackReason: String?
	public var usage: Usage?

	public init(
		sessionId: String? = nil,
		costUsd: Double,
		source: String,
		fallbackReason: String? = nil,
		usage: Usage? = nil
	) {
		self.sessionId = sessionId
		self.costUsd = costUsd
		self.source = source
		self.fallbackReason = fallbackReason
		self.usage = usage
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
		costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd) ?? 0
		source = try container.decodeIfPresent(String.self, forKey: .source) ?? HomerCostSource.cli
		fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
		usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
	}

	private enum CodingKeys: String, CodingKey {
		case sessionId, costUsd, source, fallbackReason, usage
	}

	/// The figure as charged, or "not reported" when nothing priced it (the console's
	/// `stepCostLabel`).
	public var costText: String {
		source == HomerCostSource.none ? HomerCostSource.label(source) : HomerFormat.cost(costUsd)
	}

	/// The fallback reason as it reads beside the source (`costReasonText`): a `session` reason
	/// (`incomplete: 3 of 5 calls ingested`) is no fallback, any other is one.
	public var fallbackText: String? {
		fallbackReason.map { source == HomerCostSource.session ? $0 : "fallback: \($0)" }
	}
}

/// The price sources of a cost figure, a command's (`HomerLLMAccounting.source`) or a run's
/// (`HomerProcess.costSource`, which can also be `mixed`), worded as the console's
/// `lib/utils/cost-source.ts` words them.
public nonisolated enum HomerCostSource {
	/// The operator's session-spend endpoint (`llmPrice.sessionSpend`) priced it.
	public static let session = "session"
	/// The Claude CLI's own estimate from its built-in rate card.
	public static let cli = "cli"
	/// The run's commands were priced by more than one source.
	public static let mixed = "mixed"
	/// Nothing priced it, and nothing was charged.
	public static let none = "none"

	/// The pill's text; an unknown source reads as itself. A missing one is `cli`, the server's
	/// default.
	public static func label(_ source: String?) -> String {
		switch source ?? cli {
		case session:
			"proxy"
		case cli:
			"CLI estimate"
		case mixed:
			"mixed"
		case none:
			"not reported"
		case let other:
			other
		}
	}

	/// The pill's tooltip.
	public static func explanation(_ source: String?) -> String {
		switch source ?? cli {
		case session:
			"Priced by the configured session-spend endpoint (llmPrice.sessionSpend)."
		case cli:
			"Estimated by the Claude CLI from its built-in Anthropic rate card. Behind an LLM proxy this is not what you were billed."
		case mixed:
			"Charges on this run came from more than one price source."
		case none:
			"The CLI reported no cost and no session-spend endpoint answered; nothing was charged."
		default:
			"Price source reported by the server."
		}
	}
}
