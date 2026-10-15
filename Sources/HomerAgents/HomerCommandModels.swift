import Foundation

/// A command of the instance's Slack connector (a `workflows` entry of homer-slack's
/// `config.yaml`), as Homer serves it from `GET /api/v1/commands`: the first word of
/// `<command> <text>` picks it, and the rest of the text runs `agent` under `promptParam`.
/// `command` is `""` for the default one, which takes the whole text.
public nonisolated struct HomerCommand: Equatable, Sendable, Decodable, Identifiable {
	/// Where the run reads its inputs from: the query or a JSON body.
	public enum Mode: String, Equatable, Sendable {
		case query
		case body
	}

	public var command: String
	public var agent: String
	public var description: String?
	public var mode: Mode
	public var promptParam: String
	/// Inputs sent on every run, under the prompt.
	public var staticInputs: [String: String]

	package init(
		command: String,
		agent: String,
		description: String? = nil,
		mode: Mode = .query,
		promptParam: String = "prompt",
		staticInputs: [String: String] = [:]
	) {
		self.command = command
		self.agent = agent
		self.description = description
		self.mode = mode
		self.promptParam = promptParam
		self.staticInputs = staticInputs
	}

	public var id: String {
		command
	}

	public var isDefault: Bool {
		command.isEmpty
	}

	private enum CodingKeys: String, CodingKey {
		case command
		case agent
		case description
		case mode
		case promptParam
		case staticInputs = "static"
	}

	/// The connector's defaults stand in for a missing field, as its config schema does.
	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
		self.agent = try container.decode(String.self, forKey: .agent)
		self.description = try container.decodeIfPresent(String.self, forKey: .description)
		self.mode = try container.decodeIfPresent(String.self, forKey: .mode).flatMap(Mode.init(rawValue:)) ?? .query
		self.promptParam = try container.decodeIfPresent(String.self, forKey: .promptParam) ?? "prompt"
		self.staticInputs = try container.decodeIfPresent([String: String].self, forKey: .staticInputs) ?? [:]
	}

	/// The run the connector's `trigger` starts: the static inputs, then the prompt under
	/// `promptParam` (replacing a static one of that name) unless it is empty — in the query or
	/// as a JSON body, a body always sent in body mode. Static inputs go in name order, since
	/// JSON object order is lost in decoding.
	public func runRequest(prompt: String) -> HomerAgentRunRequest {
		var inputs = staticInputs.sorted { $0.key < $1.key }.map { HomerAgentRunRequest.Field($0.key, $0.value) }
		if !prompt.isEmpty {
			if let index = inputs.firstIndex(where: { $0.name == promptParam }) {
				inputs[index].value = prompt
			}
			else {
				inputs.append(HomerAgentRunRequest.Field(promptParam, prompt))
			}
		}
		switch mode {
		case .query:
			return HomerAgentRunRequest(queryItems: inputs.map { URLQueryItem(name: $0.name, value: $0.value) })
		case .body:
			return HomerAgentRunRequest(bodyFields: inputs)
		}
	}
}

/// `GET /api/v1/commands`: the connector's commands whose agent the user may run, and the
/// connector's `help.intro`.
public nonisolated struct HomerCommandList: Equatable, Sendable, Decodable {
	public var intro: String?
	public var commands: [HomerCommand]

	package init(intro: String? = nil, commands: [HomerCommand]) {
		self.intro = intro
		self.commands = commands
	}
}
