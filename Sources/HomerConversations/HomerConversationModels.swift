import Foundation
import HomerCore

// Mirrors of the conversation proxy's JSON (its README's API contract). As with the Homer
// models, unknown enum values decode as `.unknown` so a newer proxy keeps working, and
// timestamps are Unix epoch seconds.

/// The client the proxy knows this token by (`GET /me`); its name is the author of what the
/// app sends.
public nonisolated struct HomerProxyUser: Equatable, Sendable, Decodable {
	public var name: String

	public init(name: String) {
		self.name = name
	}
}

/// A workflow of the connector's configuration (`GET /workflows`): the command word that picks
/// it and the agent it runs. The command `""` is the default workflow.
public nonisolated struct HomerWorkflow: Equatable, Sendable, Identifiable, Decodable {
	public var command: String
	public var agent: String
	public var description: String
	public var followUps: String?

	public init(command: String, agent: String, description: String = "", followUps: String? = nil) {
		self.command = command
		self.agent = agent
		self.description = description
		self.followUps = followUps
	}

	public var id: String {
		command
	}

	public var isDefault: Bool {
		command.isEmpty
	}

	/// What the composer's picker shows.
	public var title: String {
		isDefault ? "Default (\(agent))" : command
	}
}

/// Where a conversation or a run came from.
public nonisolated enum HomerConversationOrigin: String, Sendable, Hashable, Decodable {
	case slack
	case app
	case unknown

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.lowercased()) ?? .unknown
	}

	public var systemImage: String {
		switch self {
		case .slack:
			"number"
		case .app:
			"laptopcomputer"
		case .unknown:
			"questionmark.circle"
		}
	}

	public var title: String {
		switch self {
		case .slack:
			"Slack"
		case .app:
			"App"
		case .unknown:
			"Unknown"
		}
	}
}

/// One thread: a Slack thread the connector ran a workflow in, or one started from the app.
public nonisolated struct HomerConversation: Equatable, Sendable, Identifiable, Decodable {
	/// The last message, for the list's preview.
	public nonisolated struct LastMessage: Equatable, Sendable, Decodable {
		public var role: HomerConversationMessage.Role
		public var author: String
		public var preview: String
		public var createdAt: Double

		public init(role: HomerConversationMessage.Role, author: String, preview: String, createdAt: Double) {
			self.role = role
			self.author = author
			self.preview = preview
			self.createdAt = createdAt
		}
	}

	/// The thread key: the Slack thread ts, or the id the proxy minted for an app conversation.
	public var id: String
	public var origin: HomerConversationOrigin
	public var workflowCommand: String
	public var agent: String
	public var slackChannel: String?
	public var slackTeam: String?
	public var title: String
	public var createdAt: Double
	public var updatedAt: Double
	/// A run of the conversation is still going.
	public var inFlight: Bool
	public var runCount: Int
	public var lastMessage: LastMessage?

	public init(
		id: String,
		origin: HomerConversationOrigin,
		workflowCommand: String = "",
		agent: String,
		slackChannel: String? = nil,
		slackTeam: String? = nil,
		title: String,
		createdAt: Double,
		updatedAt: Double,
		inFlight: Bool = false,
		runCount: Int = 0,
		lastMessage: LastMessage? = nil
	) {
		self.id = id
		self.origin = origin
		self.workflowCommand = workflowCommand
		self.agent = agent
		self.slackChannel = slackChannel
		self.slackTeam = slackTeam
		self.title = title
		self.createdAt = createdAt
		self.updatedAt = updatedAt
		self.inFlight = inFlight
		self.runCount = runCount
		self.lastMessage = lastMessage
	}
}

/// A turn of a conversation: what someone asked, what the agent answered, or a note about a
/// run that did not end in an answer.
public nonisolated struct HomerConversationMessage: Equatable, Sendable, Identifiable, Decodable {
	public nonisolated enum Role: String, Sendable, Hashable, Decodable {
		case user
		case assistant
		case system
		case unknown

		public init(from decoder: any Decoder) throws {
			let raw = try decoder.singleValueContainer().decode(String.self)
			self = Self(rawValue: raw.lowercased()) ?? .unknown
		}
	}

	public var id: Int
	public var conversationId: String
	/// The run a user message started, or the run an assistant or system message came from.
	public var runId: Int?
	public var role: Role
	/// A client's name, `slack:<channel>` for a turn the connector forwarded, or the agent.
	public var author: String
	public var text: String
	public var slackMessageTs: String?
	public var createdAt: Double

	public init(
		id: Int,
		conversationId: String,
		runId: Int? = nil,
		role: Role,
		author: String,
		text: String,
		slackMessageTs: String? = nil,
		createdAt: Double
	) {
		self.id = id
		self.conversationId = conversationId
		self.runId = runId
		self.role = role
		self.author = author
		self.text = text
		self.slackMessageTs = slackMessageTs
		self.createdAt = createdAt
	}
}

/// One run of a conversation's workflow — one or more Homer processes, when the agent parks and
/// resumes — as the proxy follows it.
public nonisolated struct HomerConversationRun: Equatable, Sendable, Identifiable, Decodable {
	/// Where the proxy's follower is with the run. Beyond Homer's own statuses it tells a parked
	/// graph, a follow that timed out and a follow that broke apart.
	public nonisolated enum State: String, Sendable, Hashable, Decodable {
		case queued
		case running
		case waitingResume
		case finished
		case failed
		case killed
		case unknown
		case parked
		case timeout
		case error

		public init(from decoder: any Decoder) throws {
			let raw = try decoder.singleValueContainer().decode(String.self)
			self = Self(rawValue: raw) ?? Self(rawValue: raw.lowercased()) ?? .unknown
		}

		/// Still being followed.
		public var isActive: Bool {
			switch self {
			case .queued, .running, .waitingResume:
				true
			default:
				false
			}
		}

		/// The Homer status this stands for, for the shared badge; nil for the states that are
		/// the proxy's own.
		public var processStatus: HomerProcessStatus? {
			switch self {
			case .queued:
				.created
			case .running:
				.working
			case .finished:
				.finished
			case .failed:
				.failed
			case .killed:
				.killed
			case .unknown:
				.unknown
			case .waitingResume, .parked, .timeout, .error:
				nil
			}
		}

		public var title: String {
			switch self {
			case .queued:
				"Queued"
			case .running:
				"Running"
			case .waitingResume:
				"Waiting to resume"
			case .finished:
				"Finished"
			case .failed:
				"Failed"
			case .killed:
				"Killed"
			case .unknown:
				"Unknown"
			case .parked:
				"Parked"
			case .timeout:
				"Timed out"
			case .error:
				"Error"
			}
		}
	}

	public var id: Int
	public var conversationId: String
	public var origin: HomerConversationOrigin
	public var startedBy: String
	public var agent: String
	public var workflowCommand: String
	/// The process the trigger started; absent for an instant between the proxy recording the
	/// run and Homer answering.
	public var rootProcessId: Int?
	public var currentProcessId: Int?
	/// Every process of the run, the root first.
	public var processIds: [Int]
	public var state: State
	public var homerStatus: HomerProcessStatus?
	public var currentCommand: String?
	public var costUsd: Double?
	public var openQuestions: Int?
	public var errorText: String?
	public var startedAt: Double
	public var endedAt: Double?
	public var updatedAt: Double

	public init(
		id: Int,
		conversationId: String,
		origin: HomerConversationOrigin,
		startedBy: String,
		agent: String,
		workflowCommand: String = "",
		rootProcessId: Int? = nil,
		currentProcessId: Int? = nil,
		processIds: [Int] = [],
		state: State,
		homerStatus: HomerProcessStatus? = nil,
		currentCommand: String? = nil,
		costUsd: Double? = nil,
		openQuestions: Int? = nil,
		errorText: String? = nil,
		startedAt: Double,
		endedAt: Double? = nil,
		updatedAt: Double
	) {
		self.id = id
		self.conversationId = conversationId
		self.origin = origin
		self.startedBy = startedBy
		self.agent = agent
		self.workflowCommand = workflowCommand
		self.rootProcessId = rootProcessId
		self.currentProcessId = currentProcessId
		self.processIds = processIds
		self.state = state
		self.homerStatus = homerStatus
		self.currentCommand = currentCommand
		self.costUsd = costUsd
		self.openQuestions = openQuestions
		self.errorText = errorText
		self.startedAt = startedAt
		self.endedAt = endedAt
		self.updatedAt = updatedAt
	}
}

/// A conversation with everything in it (`GET /conversations/{id}`), oldest first.
public nonisolated struct HomerConversationThread: Equatable, Sendable, Decodable {
	public var conversation: HomerConversation
	public var messages: [HomerConversationMessage]
	public var runs: [HomerConversationRun]

	public init(conversation: HomerConversation, messages: [HomerConversationMessage] = [], runs: [HomerConversationRun] = []) {
		self.conversation = conversation
		self.messages = messages
		self.runs = runs
	}
}

/// One page of `GET /conversations`, newest activity first; `nextCursor` reaches the older ones.
public nonisolated struct HomerConversationPage: Equatable, Sendable, Decodable {
	public var items: [HomerConversation]
	public var nextCursor: String?

	public init(items: [HomerConversation], nextCursor: String? = nil) {
		self.items = items
		self.nextCursor = nextCursor
	}
}

/// What `POST /conversations` answers: the new conversation, its first message and the run it
/// started.
public nonisolated struct HomerConversationCreated: Equatable, Sendable, Decodable {
	public var conversation: HomerConversation
	public var message: HomerConversationMessage
	public var run: HomerConversationRun

	public init(conversation: HomerConversation, message: HomerConversationMessage, run: HomerConversationRun) {
		self.conversation = conversation
		self.message = message
		self.run = run
	}
}

/// What `POST /conversations/{id}/messages` answers: the message and the run it started.
public nonisolated struct HomerConversationReply: Equatable, Sendable, Decodable {
	public var message: HomerConversationMessage
	public var run: HomerConversationRun

	public init(message: HomerConversationMessage, run: HomerConversationRun) {
		self.message = message
		self.run = run
	}
}

/// What the proxy's event stream (`GET /events`) says, one event at a time.
public nonisolated struct HomerConversationEvent: Equatable, Sendable {
	public nonisolated enum Kind: Equatable, Sendable {
		/// The stream is open — the app's own event, sent when the response's headers arrive.
		case connected
		case conversationCreated(HomerConversation)
		case conversationUpdated(HomerConversation)
		case messageCreated(HomerConversationMessage)
		case runUpdated(HomerConversationRun)
		/// The proxy no longer holds the events after the one the stream resumed from; the
		/// client reloads what it shows.
		case reset
	}

	/// The event's sequence number, what a reconnect resumes from (`Last-Event-ID`).
	public var id: String?
	public var kind: Kind

	public init(id: String? = nil, kind: Kind) {
		self.id = id
		self.kind = kind
	}

	/// The event the stream sent, or nil for one this version does not know.
	package init?(_ event: HomerServerSentEvent) {
		let data = Data(event.data.utf8)
		let decoder = JSONDecoder()
		switch event.name {
		case "conversation.created":
			guard let conversation = try? decoder.decode(HomerConversation.self, from: data) else {
				return nil
			}
			kind = .conversationCreated(conversation)
		case "conversation.updated":
			guard let conversation = try? decoder.decode(HomerConversation.self, from: data) else {
				return nil
			}
			kind = .conversationUpdated(conversation)
		case "message.created":
			guard let message = try? decoder.decode(HomerConversationMessage.self, from: data) else {
				return nil
			}
			kind = .messageCreated(message)
		case "run.updated":
			guard let run = try? decoder.decode(HomerConversationRun.self, from: data) else {
				return nil
			}
			kind = .runUpdated(run)
		case "reset":
			kind = .reset
		default:
			return nil
		}
		id = event.id
	}
}
