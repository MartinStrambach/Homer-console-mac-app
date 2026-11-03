import Foundation
import HomerCore

// Mirrors of the Homer API's continuation JSON (`Continuation` in `console/types/homer.ts`,
// `ContinuationResponse` in the backend's `ContinuationModels.kt`). As in `HomerModels.swift`,
// only what the page shows is decoded, and timestamps are Unix epoch seconds.

/// Where a completion continuation is in its life (`ContinuationStatus`). Unknown values (a
/// newer server) decode as `.unknown` rather than failing the whole list.
public nonisolated enum HomerContinuationStatus: String, CaseIterable, Sendable, Hashable, Decodable {
	case pending = "PENDING"
	case dispatching = "DISPATCHING"
	case dispatched = "DISPATCHED"
	case failed = "FAILED"
	case cancelled = "CANCELLED"
	case expired = "EXPIRED"
	case unknown = "UNKNOWN"

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.uppercased()) ?? .unknown
	}

	/// The console's badge label (`statusStyles` in `continuation-item.tsx`).
	public var title: String {
		switch self {
		case .pending:
			"Waiting for watched run"
		case .dispatching:
			"Dispatching"
		case .dispatched:
			"Dispatched"
		case .failed:
			"Failed"
		case .cancelled:
			"Cancelled"
		case .expired:
			"Expired"
		case .unknown:
			"Unknown"
		}
	}

	/// The statuses the list's `status` filter offers, in the order a continuation goes through
	/// them.
	public static let filterable: [Self] = [.pending, .dispatching, .dispatched, .failed, .cancelled, .expired]
}

/// A parked workflow: when the watched run finishes, the server starts `agentName`.
public nonisolated struct HomerContinuation: Equatable, Sendable, Identifiable, Decodable {
	public var id: Int
	public var watchedProcessId: Int
	public var status: HomerContinuationStatus
	/// The agent started when the watched run finishes.
	public var agentName: String
	/// The run that parked the workflow, and its agent.
	public var originProcessId: Int
	public var originAgentName: String
	public var expiresAt: Double?
	public var createdAt: Double
	public var firedAt: Double?
	/// The run the continuation started, once dispatched.
	public var firedProcessId: Int?
	/// Why it failed to fire.
	public var error: String?
	/// The input of the started agent that gets the watched run's result.
	public var resumeParam: String?
	/// The other inputs it starts the agent with, secrets masked by the server.
	public var params: [String: String]?

	public init(
		id: Int,
		watchedProcessId: Int,
		status: HomerContinuationStatus,
		agentName: String,
		originProcessId: Int,
		originAgentName: String,
		expiresAt: Double? = nil,
		createdAt: Double,
		firedAt: Double? = nil,
		firedProcessId: Int? = nil,
		error: String? = nil,
		resumeParam: String? = nil,
		params: [String: String]? = nil
	) {
		self.id = id
		self.watchedProcessId = watchedProcessId
		self.status = status
		self.agentName = agentName
		self.originProcessId = originProcessId
		self.originAgentName = originAgentName
		self.expiresAt = expiresAt
		self.createdAt = createdAt
		self.firedAt = firedAt
		self.firedProcessId = firedProcessId
		self.error = error
		self.resumeParam = resumeParam
		self.params = params
	}

	/// Only a pending continuation can be cancelled; the server answers 409 for any other.
	public var isCancellable: Bool {
		status == .pending
	}
}

/// `GET /api/v1/continuations`.
nonisolated struct HomerContinuationList: Decodable {
	var continuations: [HomerContinuation]
	/// Every visible row matching the filters, before paging.
	var total: Int?
}
