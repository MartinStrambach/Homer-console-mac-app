import Foundation
import HomerCore

// Mirrors of the Homer API's dispatch JSON (`DispatchResponse` in the backend's
// `DispatchModels.kt`; the console has no dispatch list, only the summary on a question). As in
// `HomerModels.swift`, only what the page shows is decoded, and timestamps are Unix epoch seconds.

/// Where an ask-and-dispatch is in its life (`DispatchStatus`). A dispatch whose time ran out is
/// cancelled — it has no expired status of its own. Unknown values (a newer server) decode as
/// `.unknown` rather than failing the whole list.
public nonisolated enum HomerDispatchStatus: String, CaseIterable, Sendable, Hashable, Decodable {
	case pending = "PENDING"
	case dispatching = "DISPATCHING"
	case dispatched = "DISPATCHED"
	case failed = "FAILED"
	case cancelled = "CANCELLED"
	case unknown = "UNKNOWN"

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.uppercased()) ?? .unknown
	}

	/// The badge's label.
	public var title: String {
		switch self {
		case .pending:
			"Waiting for answer"
		case .dispatching:
			"Dispatching"
		case .dispatched:
			"Dispatched"
		case .failed:
			"Failed"
		case .cancelled:
			"Cancelled"
		case .unknown:
			"Unknown"
		}
	}

	/// The statuses the list's `status` filter offers, in the order a dispatch goes through them.
	public static let filterable: [Self] = [.pending, .dispatching, .dispatched, .failed, .cancelled]
}

/// An ask-and-dispatch: a question a run asked, and the agent the server starts — with the answer
/// as one of its inputs — once someone answers it.
public nonisolated struct HomerDispatch: Equatable, Sendable, Identifiable, Decodable {
	public var id: Int
	/// The question whose answer starts the agent.
	public var questionId: String
	public var status: HomerDispatchStatus
	/// The agent started once the question is answered.
	public var agentName: String
	/// The input of that agent that gets the answer.
	public var answerParam: String?
	/// The other inputs it starts the agent with, secrets masked by the server.
	public var params: [String: String]?
	/// The run that asked the question, and its agent.
	public var originProcessId: Int
	public var originAgentName: String
	/// When an unanswered question is given up on: the dispatch is cancelled then.
	public var expiresAt: Double?
	public var createdAt: Double
	public var dispatchedAt: Double?
	/// The run the answer started, once dispatched.
	public var dispatchedProcessId: Int?
	/// Why the agent failed to start.
	public var error: String?

	public init(
		id: Int,
		questionId: String,
		status: HomerDispatchStatus,
		agentName: String,
		answerParam: String? = nil,
		params: [String: String]? = nil,
		originProcessId: Int,
		originAgentName: String,
		expiresAt: Double? = nil,
		createdAt: Double,
		dispatchedAt: Double? = nil,
		dispatchedProcessId: Int? = nil,
		error: String? = nil
	) {
		self.id = id
		self.questionId = questionId
		self.status = status
		self.agentName = agentName
		self.answerParam = answerParam
		self.params = params
		self.originProcessId = originProcessId
		self.originAgentName = originAgentName
		self.expiresAt = expiresAt
		self.createdAt = createdAt
		self.dispatchedAt = dispatchedAt
		self.dispatchedProcessId = dispatchedProcessId
		self.error = error
	}

	/// Only a dispatch whose question is still open can be cancelled (which expires the
	/// question); the server answers 409 for any other.
	public var isCancellable: Bool {
		status == .pending
	}
}

/// `GET /api/v1/dispatches`.
nonisolated struct HomerDispatchList: Decodable {
	var dispatches: [HomerDispatch]
	/// Every visible row matching the filters, before paging.
	var total: Int?
}
