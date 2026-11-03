import Foundation

// Mirrors of the Homer API's JSON (`console/types/homer.ts` in the Homer repo). Only the fields
// the native lists show are decoded; anything else the server sends is ignored, so a newer
// server keeps decoding. Timestamps are Unix epoch seconds throughout.

/// A process's lifecycle state. Unknown values (a newer server) decode as `.unknown` rather than
/// failing the whole list.
public nonisolated enum HomerProcessStatus: String, CaseIterable, Sendable, Hashable, Decodable {
	case created = "CREATED"
	case working = "WORKING"
	case finished = "FINISHED"
	case failed = "FAILED"
	case killed = "KILLED"
	case unknown = "UNKNOWN"

	/// The statuses the server accepts in the list's `types` filter, in the console's order.
	public static let filterable: [Self] = [.working, .finished, .failed, .killed, .created]

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.uppercased()) ?? .unknown
	}

	public var title: String {
		rawValue.capitalized
	}
}

public nonisolated struct HomerProcess: Equatable, Sendable, Identifiable, Decodable {
	public nonisolated struct HistoryEntry: Equatable, Sendable, Decodable {
		public var timestamp: Double
		public var status: HomerProcessStatus

		public init(timestamp: Double, status: HomerProcessStatus) {
			self.timestamp = timestamp
			self.status = status
		}
	}

	/// A finished command of the run (`ProcessExecution`).
	public nonisolated struct Execution: Equatable, Sendable, Decodable {
		public var label: String
		public var resultCode: Int
		public var skipped: Bool?
		public var start: Double?
		public var end: Double?
		/// The command's output files, as the server's absolute paths — `HomerArtifactPath`
		/// turns them into what the artifact calls take.
		public var stdOut: String?
		public var stdErr: String?
		/// Why the command failed, or why it was skipped.
		public var errMsg: String?
		/// The command's type: `cmd`, `script`, `claude`, `codex`, `opencode`, `agent`,
		/// `langgraph`, `runnerCmd`; empty for older rows, nil from an older server.
		public var kind: String?
		/// The command's stdout or stderr passed the server's `maxOutputBytes`, which killed it:
		/// the file ends at the cap. Homer's `ExecutionInfo` has the flag, but its API response
		/// does not send it yet — decoded when present.
		public var outputTruncated: Bool?

		public init(
			label: String,
			resultCode: Int,
			skipped: Bool? = nil,
			start: Double? = nil,
			end: Double? = nil,
			stdOut: String? = nil,
			stdErr: String? = nil,
			errMsg: String? = nil,
			kind: String? = nil,
			outputTruncated: Bool? = nil
		) {
			self.label = label
			self.resultCode = resultCode
			self.skipped = skipped
			self.start = start
			self.end = end
			self.stdOut = stdOut
			self.stdErr = stdErr
			self.errMsg = errMsg
			self.kind = kind
			self.outputTruncated = outputTruncated
		}
	}

	/// Where the run executes (`RunnerState`). The pod fields are set only for a Kubernetes
	/// runner.
	public nonisolated struct Runner: Equatable, Sendable, Decodable {
		/// Why the run's pod never became ready (`PodStartupFailure`).
		public nonisolated struct StartupFailure: Equatable, Sendable, Decodable {
			public var reason: String
			public var message: String
			public var events: [String]

			public init(reason: String, message: String, events: [String] = []) {
				self.reason = reason
				self.message = message
				self.events = events
			}

			public init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				reason = try container.decode(String.self, forKey: .reason)
				message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
				events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
			}

			private enum CodingKeys: String, CodingKey {
				case reason, message, events
			}
		}

		/// The backend's own name for the runner. Sent to admins only — everyone else gets the
		/// generic `type` (Homer ADR-0077).
		public var alias: String?
		/// `local`, `ssh`, `kubernetes`, `external` or `unknown`. Missing from servers older than
		/// ADR-0077, which always sent the alias.
		public var type: String?
		public var podName: String?
		public var podPhase: String?
		public var createdAt: Double?
		public var readyAt: Double?
		public var endedAt: Double?
		public var startupFailure: StartupFailure?

		public init(
			alias: String? = nil,
			type: String? = nil,
			podName: String? = nil,
			podPhase: String? = nil,
			createdAt: Double? = nil,
			readyAt: Double? = nil,
			endedAt: Double? = nil,
			startupFailure: StartupFailure? = nil
		) {
			self.alias = alias
			self.type = type
			self.podName = podName
			self.podPhase = podPhase
			self.createdAt = createdAt
			self.readyAt = readyAt
			self.endedAt = endedAt
			self.startupFailure = startupFailure
		}

		/// What the console's Runner column shows.
		public var displayName: String {
			alias ?? type ?? "-"
		}
	}

	public var id: Int
	public var status: HomerProcessStatus
	public var agentName: String
	/// The agent's `group` label (Homer 1.38), read from its current definition: nil when the
	/// agent is ungrouped, has since been removed, or the server is older.
	public var group: String?
	/// Who started the run, e.g. `session:admin` or a bearer token's name.
	public var owner: String?
	public var history: [HistoryEntry]
	public var executions: [Execution]
	public var currentCommand: String?
	/// When the running command started, in epoch seconds.
	public var currentCommandStart: Double?
	/// The running command's type (`Execution.kind`); nil when nothing runs, after a server
	/// restart, or from an older server.
	public var currentCommandKind: String?
	/// When the run's workspace is deleted, in epoch seconds; nil while it runs or before the
	/// purge is scheduled.
	public var purgeAt: Double?
	public var runner: Runner?
	public var openQuestions: Int?
	/// Billed Claude spend for the run, from the server's cost ledger.
	public var costUsd: Double?
	/// The run that started this one; nil at a flow's root.
	public var parentProcessId: Int?
	/// The first run of this run's flow; nil at the root itself.
	public var rootProcessId: Int?
	public var tags: [String]?
	/// The run's Langfuse trace; nil unless the server has Langfuse configured.
	public var langfuseTraceUrl: String?
	/// Why the run ended `FAILED` before any command started — a claim timeout, a lock skip, the
	/// parallel-run cap or a full queue (Homer 1.38). A sentence the server builds, shown as
	/// plain text; nil for every other run, and from an older server.
	public var failureReason: String?
	/// The run that blocked this one — the lock holder named in `failureReason`. Homer stores it
	/// as `failureReasonRunId` but sends it only inside the sentence, as " (run #N)", and only to
	/// someone who may open that run: `blockingRunId` reads either.
	public var failureReasonRunId: Int?
	/// The artifact globs that survive the workspace purge (`workspace.retain.artifacts`,
	/// ADR-0053), captured when the run ended. Homer keeps them on the run but does not send
	/// them yet — decoded when present.
	public var retainArtifacts: [String]?
	/// Whether the server's `maxRetainedArtifactBytes` cut the retained files short at the purge;
	/// nil until the purge has run, or when nothing is retained.
	public var retainedTruncated: Bool?

	public init(
		id: Int,
		status: HomerProcessStatus,
		agentName: String,
		group: String? = nil,
		owner: String? = nil,
		history: [HistoryEntry] = [],
		executions: [Execution] = [],
		currentCommand: String? = nil,
		currentCommandStart: Double? = nil,
		currentCommandKind: String? = nil,
		purgeAt: Double? = nil,
		runner: Runner? = nil,
		openQuestions: Int? = nil,
		costUsd: Double? = nil,
		parentProcessId: Int? = nil,
		rootProcessId: Int? = nil,
		tags: [String]? = nil,
		langfuseTraceUrl: String? = nil,
		failureReason: String? = nil,
		failureReasonRunId: Int? = nil,
		retainArtifacts: [String]? = nil,
		retainedTruncated: Bool? = nil
	) {
		self.id = id
		self.status = status
		self.agentName = agentName
		self.group = group
		self.owner = owner
		self.history = history
		self.executions = executions
		self.currentCommand = currentCommand
		self.currentCommandStart = currentCommandStart
		self.currentCommandKind = currentCommandKind
		self.purgeAt = purgeAt
		self.runner = runner
		self.openQuestions = openQuestions
		self.costUsd = costUsd
		self.parentProcessId = parentProcessId
		self.rootProcessId = rootProcessId
		self.tags = tags
		self.langfuseTraceUrl = langfuseTraceUrl
		self.failureReason = failureReason
		self.failureReasonRunId = failureReasonRunId
		self.retainArtifacts = retainArtifacts
		self.retainedTruncated = retainedTruncated
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(Int.self, forKey: .id)
		status = try container.decode(HomerProcessStatus.self, forKey: .status)
		agentName = try container.decode(String.self, forKey: .agentName)
		group = try container.decodeIfPresent(String.self, forKey: .group)
		owner = try container.decodeIfPresent(String.self, forKey: .owner)
		// Both are always sent today, but an absent array means "none", not a broken process.
		history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
		executions = try container.decodeIfPresent([Execution].self, forKey: .executions) ?? []
		currentCommand = try container.decodeIfPresent(String.self, forKey: .currentCommand)
		currentCommandStart = try container.decodeIfPresent(Double.self, forKey: .currentCommandStart)
		currentCommandKind = try container.decodeIfPresent(String.self, forKey: .currentCommandKind)
		purgeAt = try container.decodeIfPresent(Double.self, forKey: .purgeAt)
		runner = try container.decodeIfPresent(Runner.self, forKey: .runner)
		openQuestions = try container.decodeIfPresent(Int.self, forKey: .openQuestions)
		costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
		parentProcessId = try container.decodeIfPresent(Int.self, forKey: .parentProcessId)
		rootProcessId = try container.decodeIfPresent(Int.self, forKey: .rootProcessId)
		tags = try container.decodeIfPresent([String].self, forKey: .tags)
		langfuseTraceUrl = try container.decodeIfPresent(String.self, forKey: .langfuseTraceUrl)
		failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
		failureReasonRunId = try container.decodeIfPresent(Int.self, forKey: .failureReasonRunId)
		retainArtifacts = try container.decodeIfPresent([String].self, forKey: .retainArtifacts)
		retainedTruncated = try container.decodeIfPresent(Bool.self, forKey: .retainedTruncated)
	}

	private enum CodingKeys: String, CodingKey {
		case id, status, agentName, group, owner, history, executions, currentCommand, currentCommandStart
		case currentCommandKind
		case purgeAt, runner, openQuestions, costUsd, parentProcessId, rootProcessId, tags
		case langfuseTraceUrl, failureReason, failureReasonRunId, retainArtifacts, retainedTruncated
	}

	/// The run that blocked this one from starting (a lock holder): `failureReasonRunId`, or the
	/// " (run #N)" the server appends to `failureReason`. Nil when the reason names no run, or
	/// names one the user may not open.
	public var blockingRunId: Int? {
		failureReasonRunId ?? failureReason.flatMap { Self.blockingRunSuffix(in: $0)?.runId }
	}

	/// `failureReason` without the " (run #N)" that names the blocking run, which the page shows
	/// as a link of its own.
	public var failureReasonSentence: String? {
		guard let failureReason else {
			return nil
		}
		guard let suffix = Self.blockingRunSuffix(in: failureReason) else {
			return failureReason
		}
		return String(failureReason[..<suffix.range.lowerBound])
	}

	/// The " (run #N)" `ResponseMapping.kt` appends to a failure reason, at its very end.
	private static func blockingRunSuffix(in reason: String) -> (runId: Int, range: Range<String.Index>)? {
		guard let match = reason.firstMatch(of: /\s*\(run #(\d+)\)$/), let runId = Int(match.1) else {
			return nil
		}
		return (runId, match.range)
	}

	/// A run a cron tick started, or one of its sub-runs: the scheduler stamps its runs' owner
	/// `system:cron` and sub-runs inherit it (Homer's SERVER.md, "Process ownership").
	public var isScheduled: Bool {
		owner == "system:cron"
	}

	/// A run that can still be killed (the console's `canKill`).
	public var isKillable: Bool {
		status == .working || status == .created
	}

	/// A run that has ended and can be started again with the same inputs (`canRetry`).
	public var isRetryable: Bool {
		status == .finished || status == .failed || status == .killed
	}

	/// A run the console offers to resume from its LangGraph checkpoint — if it has one, which
	/// only the LangGraph probe tells (`resumeEligible` on the process page).
	public var isResumeEligible: Bool {
		status == .failed || status == .killed || status == .unknown
	}

	public enum LastCommandOutcome: Equatable, Sendable {
		case running
		case succeeded
		case failed
	}

	/// One square of the process list's command row (`CommandDot`, Homer 1.39).
	public nonisolated struct CommandDot: Equatable, Sendable {
		public var label: String
		public var outcome: LastCommandOutcome

		public init(label: String, outcome: LastCommandOutcome) {
			self.label = label
			self.outcome = outcome
		}
	}

	/// One dot per command the run executed, then the running one while it works
	/// (`commandDotStates` in `lib/utils/process.ts`). A command its `when:` skipped never ran
	/// and gets none; nor do commands still ahead, since the list does not say how many there are.
	public var commandDots: [CommandDot] {
		var dots = executions.filter { $0.skipped != true }.map {
			CommandDot(label: $0.label, outcome: $0.resultCode == 0 ? .succeeded : .failed)
		}
		if status == .working, let currentCommand {
			dots.append(CommandDot(label: currentCommand, outcome: .running))
		}
		return dots
	}

	/// The console's "Last Command" column (`lastCommandFromDots`): the last of `commandDots` —
	/// the running command of a working process, else the most recent execution that ran.
	/// Trailing skips are passed over (Homer 1.37.1), and a run whose every command was skipped
	/// has none.
	public var lastCommand: (outcome: LastCommandOutcome, label: String)? {
		commandDots.last.map { ($0.outcome, $0.label) }
	}

	/// How long the whole run has gone on, in seconds (`runDurationSeconds`, the list's Duration
	/// column since Homer 1.39): from its first status change to its last, or to `now` while it
	/// is created or working. Nil without a history, or when the span would be negative.
	public func duration(now: Date) -> TimeInterval? {
		guard let start = history.first?.timestamp, let last = history.last?.timestamp else {
			return nil
		}
		let end = isKillable ? now.timeIntervalSince1970 : last
		let seconds = end - start
		return seconds.isFinite && seconds >= 0 ? seconds : nil
	}
}

/// One page of `GET /api/v1/status/all`.
public nonisolated struct HomerProcessPage: Equatable, Sendable, Decodable {
	public var processes: [HomerProcess]
	public var total: Int

	public init(processes: [HomerProcess], total: Int) {
		self.processes = processes
		self.total = total
	}
}

/// Which runs the process list asks for — the web console's filters (`useProcesses`).
public nonisolated struct HomerProcessQuery: Equatable, Sendable {
	public var statuses: Set<HomerProcessStatus>
	/// Only the first run of each flow (the console's "Root runs" view).
	public var rootsOnly: Bool
	public var agentName: String?
	/// Runs carrying every one of these subject tags.
	public var tags: [String]
	/// The direct children of one run.
	public var parentProcessId: Int?
	/// Every run of one flow below its root — what a Flow cell summarizes.
	public var rootProcessId: Int?
	public var oldestFirst: Bool
	public var limit: Int
	/// Rows skipped from the top: the lists always read from 0, reading every match pages on.
	public var offset: Int

	public init(
		statuses: Set<HomerProcessStatus> = [],
		rootsOnly: Bool = false,
		agentName: String? = nil,
		tags: [String] = [],
		parentProcessId: Int? = nil,
		rootProcessId: Int? = nil,
		oldestFirst: Bool = false,
		limit: Int,
		offset: Int = 0
	) {
		self.statuses = statuses
		self.rootsOnly = rootsOnly
		self.agentName = agentName
		self.tags = tags
		self.parentProcessId = parentProcessId
		self.rootProcessId = rootProcessId
		self.oldestFirst = oldestFirst
		self.limit = limit
		self.offset = offset
	}

	/// Query items in the order the console sends them. A list's refresh always re-reads from the
	/// top (offset 0), so pages loaded with "Load more" stay fresh too.
	var queryItems: [URLQueryItem] {
		var items: [URLQueryItem] = []
		let types = HomerProcessStatus.filterable.filter(statuses.contains).map(\.rawValue)
		if !types.isEmpty {
			items.append(URLQueryItem(name: "types", value: types.joined(separator: ",")))
		}
		if let agentName {
			items.append(URLQueryItem(name: "agentName", value: agentName))
		}
		if let parentProcessId {
			items.append(URLQueryItem(name: "parentProcessId", value: String(parentProcessId)))
		}
		if let rootProcessId {
			items.append(URLQueryItem(name: "rootProcessId", value: String(rootProcessId)))
		}
		if rootsOnly {
			items.append(URLQueryItem(name: "roots", value: "true"))
		}
		items += tags.map { URLQueryItem(name: "tag", value: $0) }
		items.append(URLQueryItem(name: "order", value: oldestFirst ? "asc" : "desc"))
		items.append(URLQueryItem(name: "limit", value: String(limit)))
		items.append(URLQueryItem(name: "offset", value: String(offset)))
		return items
	}
}

/// The Flow cell of a root run (`flow-summary-cell.tsx`): the runs under it, what they cost
/// together and their aggregate state. The root's own status and cost are in its row already.
public nonisolated struct HomerFlowSummary: Equatable, Sendable {
	/// Aggregate state, most actionable first.
	public enum State: Equatable, Sendable {
		case question
		case running
		case failed
		case finished
	}

	/// Runs fetched per root. The count comes from the page's `total`, so the cap bounds only
	/// the cost sum and the state.
	public static let fetchLimit = 100

	public var runCount: Int
	public var costUsd: Double
	public var state: State?
	/// More runs than were fetched: cost and state cover the newest `fetchLimit` only.
	public var isPartial: Bool

	public init(runCount: Int, costUsd: Double, state: State?, isPartial: Bool) {
		self.runCount = runCount
		self.costUsd = costUsd
		self.state = state
		self.isPartial = isPartial
	}

	/// The question check comes first: a question exists only while its run is working, so
	/// ranking `running` above it would make that state unreachable. Killed reads as failed.
	public init(page: HomerProcessPage) {
		let runs = page.processes
		self.runCount = page.total
		self.costUsd = runs.reduce(0) { $0 + ($1.costUsd ?? 0) }
		self.isPartial = page.total > runs.count
		self.state =
			if runs.isEmpty {
				nil
			}
			else if runs.contains(where: { ($0.openQuestions ?? 0) > 0 }) {
				.question
			}
			else if runs.contains(where: { $0.status == .working || $0.status == .created }) {
				.running
			}
			else if runs.contains(where: { $0.status == .failed || $0.status == .killed }) {
				.failed
			}
			else {
				.finished
			}
	}
}

public nonisolated enum HomerQuestionStatus: String, Sendable, Hashable, Decodable {
	case open = "OPEN"
	case answered = "ANSWERED"
	case expired = "EXPIRED"
	case unknown

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.uppercased()) ?? .unknown
	}
}

/// A human-in-the-loop question a running command asked (`GET /api/v1/questions`).
public nonisolated struct HomerQuestion: Equatable, Sendable, Identifiable, Decodable {
	/// Present when answering the question starts another agent (ask-and-dispatch).
	public nonisolated struct Dispatch: Equatable, Sendable, Decodable {
		/// What `DELETE /api/v1/dispatches/{id}` cancels — the question with it.
		public var id: Int?
		public var agentName: String
		/// `PENDING` until the question is answered, then `DISPATCHING`, `DISPATCHED` or `FAILED`;
		/// `CANCELLED` once cancelled or expired.
		public var status: String
		public var dispatchedProcessId: Int?
		public var error: String?

		public init(
			id: Int? = nil,
			agentName: String,
			status: String,
			dispatchedProcessId: Int? = nil,
			error: String? = nil
		) {
			self.id = id
			self.agentName = agentName
			self.status = status
			self.dispatchedProcessId = dispatchedProcessId
			self.error = error
		}

		/// The run answering started, once it has.
		public var startedProcessId: Int? {
			status.uppercased() == "DISPATCHED" ? dispatchedProcessId : nil
		}

		public var hasFailed: Bool {
			status.uppercased() == "FAILED"
		}
	}

	public var id: String
	public var processId: Int
	public var agentName: String
	/// Markdown written by the agent.
	public var text: String
	/// Predefined answers, offered as buttons. May be empty: then only a free-text answer fits.
	public var options: [String]
	public var status: HomerQuestionStatus
	public var answer: String?
	public var createdAt: Double
	public var answeredAt: Double?
	public var dispatch: Dispatch?

	public init(
		id: String,
		processId: Int,
		agentName: String,
		text: String,
		options: [String] = [],
		status: HomerQuestionStatus = .open,
		answer: String? = nil,
		createdAt: Double,
		answeredAt: Double? = nil,
		dispatch: Dispatch? = nil
	) {
		self.id = id
		self.processId = processId
		self.agentName = agentName
		self.text = text
		self.options = options
		self.status = status
		self.answer = answer
		self.createdAt = createdAt
		self.answeredAt = answeredAt
		self.dispatch = dispatch
	}

	public var createdDate: Date {
		Date(timeIntervalSince1970: createdAt)
	}
}

/// A page of `GET /api/v1/questions`, oldest first. Since Homer 1.34 the list is paged (100 by
/// default) and `total` counts every visible question matching the filters; an older server sends
/// every question and no `total`.
public nonisolated struct HomerQuestionPage: Equatable, Sendable, Decodable {
	public var questions: [HomerQuestion]
	public var total: Int

	public init(questions: [HomerQuestion], total: Int? = nil) {
		self.questions = questions
		self.total = total ?? questions.count
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(
			questions: container.decode([HomerQuestion].self, forKey: .questions),
			total: container.decodeIfPresent(Int.self, forKey: .total)
		)
	}

	private enum CodingKeys: String, CodingKey {
		case questions, total
	}
}

/// The signed-in principal (`GET /api/v1/auth/me`).
public nonisolated struct HomerUser: Equatable, Sendable, Decodable {
	/// What the user may do on which agents. `agents` are names or prefix patterns ending in
	/// `*`; `actions` are `run`, `read`, `control`, `edit`, `debug`.
	public nonisolated struct Grant: Equatable, Sendable, Decodable {
		public var agents: [String]
		public var actions: [String]

		public init(agents: [String], actions: [String]) {
			self.agents = agents
			self.actions = actions
		}
	}

	public var username: String
	public var role: String?
	public var grants: [Grant]

	public init(username: String, role: String? = nil, grants: [Grant] = []) {
		self.username = username
		self.role = role
		self.grants = grants
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		username = try container.decode(String.self, forKey: .username)
		role = try container.decodeIfPresent(String.self, forKey: .role)
		grants = try container.decodeIfPresent([Grant].self, forKey: .grants) ?? []
	}

	private enum CodingKeys: String, CodingKey {
		case username, role, grants
	}

	public var isAdmin: Bool {
		role == "admin"
	}

	// The console's `capabilitiesFor` (`lib/auth/use-can.ts`): it only decides which buttons to
	// offer — the server checks every call again.

	public func canKill(_ process: HomerProcess) -> Bool {
		isAdmin || owns(process) || (canSee(process) && can("control", agent: process.agentName))
	}

	public func canRetry(_ process: HomerProcess) -> Bool {
		canSee(process) && can("run", agent: process.agentName)
	}

	private func canSee(_ process: HomerProcess) -> Bool {
		isAdmin || owns(process) || can("read", agent: process.agentName)
	}

	/// A console session's runs are owned by `session:<username>`.
	private func owns(_ process: HomerProcess) -> Bool {
		isAdmin || process.owner == "session:\(username)"
	}

	private func can(_ action: String, agent: String) -> Bool {
		isAdmin || grants.contains { grant in
			grant.actions.contains(action) && grant.agents.contains { Self.agentPattern($0, matches: agent) }
		}
	}

	/// Homer's `AgentNameMatcher`: `*` matches every agent, `prefix*` a prefix, else exact.
	package static func agentPattern(_ pattern: String, matches name: String) -> Bool {
		if pattern == "*" {
			return true
		}
		if pattern.hasSuffix("*") {
			return name.hasPrefix(pattern.dropLast())
		}
		return pattern == name
	}
}

nonisolated struct HomerAgentList: Decodable {
	nonisolated struct Agent: Decodable {
		var name: String
	}

	var agents: [Agent]
}

package nonisolated struct HomerRetryResponse: Decodable {
	package var processId: Int
}

/// An LLM harness a command runs — the command types whose stdout the server translates into
/// conversation events (`isLlmKind` in `types/homer.ts`): Claude Code, Codex and, since Homer
/// 1.39, opencode.
public nonisolated enum HomerLLMHarness: String, CaseIterable, Equatable, Sendable {
	case claude
	case codex
	case opencode

	/// The harness a command of this `kind` runs; nil for any other command, or an older row.
	public init?(kind: String?) {
		guard let kind, let harness = Self(rawValue: kind) else {
			return nil
		}
		self = harness
	}

	/// The harness's own name, as its tool spells it.
	public var title: String {
		switch self {
		case .claude:
			"Claude"
		case .codex:
			"Codex"
		case .opencode:
			"opencode"
		}
	}
}
