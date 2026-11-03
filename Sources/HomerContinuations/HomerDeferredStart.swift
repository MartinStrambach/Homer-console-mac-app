import ComposableArchitecture
import Foundation
import HomerCore

// What a continuation and an ask-and-dispatch share: an agent the server starts later — once a
// watched run ends, or once a question is answered — on behalf of the run that asked for it. Both
// are listed, filtered, paged and cancelled the same way (`/continuations`, `/dispatches`), so one
// list reducer and one card serve the two.

/// A continuation's or a dispatch's status.
public protocol HomerDeferredStatus: Hashable, Sendable {
	static var pending: Self { get }
	static var dispatched: Self { get }
	static var failed: Self { get }
	/// What the list's status filter offers.
	static var filterable: [Self] { get }
	/// The badge's label.
	var title: String { get }
	/// The server's name, which the `status` query takes.
	var rawValue: String { get }
}

extension HomerDeferredStatus {
	/// The status filter's label: the server's word, not the badge's sentence.
	var filterTitle: String {
		rawValue.capitalized
	}
}

extension HomerContinuationStatus: HomerDeferredStatus {}
extension HomerDispatchStatus: HomerDeferredStatus {}

/// A continuation or a dispatch, as the list, its cards and the detail sheet read them.
public protocol HomerDeferredStart: Equatable, Sendable, Identifiable where ID == Int {
	associatedtype Status: HomerDeferredStatus
	var status: Status { get }
	/// The agent the server starts.
	var agentName: String { get }
	/// The run that asked for the start, and its agent.
	var originProcessId: Int { get }
	var originAgentName: String { get }
	/// When a pending one is given up on.
	var expiresAt: Double? { get }
	var createdAt: Double { get }
	/// When the agent was started, and the run that start made.
	var startedAt: Double? { get }
	var startedProcessId: Int? { get }
	/// Why the agent failed to start.
	var error: String? { get }
	/// The inputs it starts the agent with, secrets masked by the server.
	var params: [String: String]? { get }
	var isCancellable: Bool { get }
}

extension HomerContinuation: HomerDeferredStart {
	public var startedAt: Double? {
		firedAt
	}

	public var startedProcessId: Int? {
		firedProcessId
	}
}

extension HomerDispatch: HomerDeferredStart {
	public var startedAt: Double? {
		dispatchedAt
	}

	public var startedProcessId: Int? {
		dispatchedProcessId
	}
}

extension HomerDeferredStart {
	/// Pending, and due to be given up on within `HomerExpiry.soonWindow` of `now`.
	func isExpiringSoon(now: Date) -> Bool {
		guard status == .pending, let expiresAt else {
			return false
		}
		let left = expiresAt - now.timeIntervalSince1970
		return left <= HomerExpiry.soonWindow
	}
}

nonisolated enum HomerExpiry {
	/// What counts as expiring soon: a question an hour from being given up on wants an answer now.
	static let soonWindow: TimeInterval = 60 * 60

	/// The soonest to expire first, those that never expire last; the newest first among equals,
	/// as the server orders them.
	static func soonestFirst<Record: HomerDeferredStart>(_ records: [Record]) -> [Record] {
		records.sorted { lhs, rhs in
			switch (lhs.expiresAt, rhs.expiresAt) {
			case let (left?, right?) where left != right:
				left < right
			case (.some, nil):
				true
			case (nil, .some):
				false
			default:
				lhs.createdAt > rhs.createdAt
			}
		}
	}
}

/// Which records a list shows.
public enum HomerRecordFilter<Status: HomerDeferredStatus>: Hashable, Sendable {
	/// What needs attention: the pending ones, soonest to expire first, then those that failed
	/// to start their agent.
	case open
	/// Every status, newest first.
	case all
	case status(Status)

	/// The status the server is asked for; nil for every status.
	var queriedStatus: Status? {
		if case let .status(status) = self {
			return status
		}
		return nil
	}
}

/// One list request: `?status=&agentName=&limit=`.
public struct HomerRecordQuery<Status: HomerDeferredStatus>: Equatable, Sendable {
	public var status: Status?
	/// The agent the records start.
	public var agentName: String?
	public var limit: Int

	public init(status: Status? = nil, agentName: String? = nil, limit: Int = 100) {
		self.status = status
		self.agentName = agentName
		self.limit = limit
	}

	var queryItems: [URLQueryItem] {
		var items = [URLQueryItem(name: "limit", value: String(limit))]
		if let status {
			items.append(URLQueryItem(name: "status", value: status.rawValue))
		}
		if let agentName {
			items.append(URLQueryItem(name: "agentName", value: agentName))
		}
		return items
	}
}

/// One page of a list, newest first, and how many match past it.
public struct HomerRecordPage<Record: HomerDeferredStart>: Equatable, Sendable {
	public var items: [Record]
	public var total: Int

	public init(items: [Record], total: Int? = nil) {
		self.items = items
		self.total = max(total ?? items.count, items.count)
	}
}

/// What sets the two lists apart: their calls and their words.
public protocol HomerRecordKind: Sendable {
	associatedtype Record: HomerDeferredStart
	/// "continuation" or "dispatch".
	static var noun: String { get }
	static func page(
		_ client: HomerContinuationsClient,
		baseURL: String,
		query: HomerRecordQuery<Record.Status>
	) async throws -> HomerRecordPage<Record>
	static func cancel(_ client: HomerContinuationsClient, baseURL: String, id: Int) async throws
	/// What Cancel asks first.
	static func cancelAlert(_ record: Record) -> (title: String, message: String, confirm: String, keep: String)
	/// What a cancel's 409 or 404 says: the list was stale.
	static var notCancellableMessage: String { get }
	/// What the instance is told after a cancel, besides the list refetching.
	static var changedDelegates: [HomerPageDelegate] { get }
}

public enum HomerContinuationKind: HomerRecordKind {
	public static let noun = "continuation"

	public static func page(
		_ client: HomerContinuationsClient,
		baseURL: String,
		query: HomerRecordQuery<HomerContinuationStatus>
	) async throws -> HomerRecordPage<HomerContinuation> {
		try await client.continuations(baseURL, query)
	}

	public static func cancel(_ client: HomerContinuationsClient, baseURL: String, id: Int) async throws {
		try await client.cancel(baseURL, id)
	}

	public static func cancelAlert(_ continuation: HomerContinuation) -> (title: String, message: String, confirm: String, keep: String) {
		(
			"Cancel this continuation?",
			"This stops \(continuation.agentName) from starting when run #\(continuation.watchedProcessId) finishes. This cannot be undone.",
			"Yes, Cancel",
			"Keep Waiting"
		)
	}

	public static let notCancellableMessage =
		"This continuation can no longer be cancelled — it already fired or was cancelled."

	/// The page picker's count of pending continuations is re-read.
	public static let changedDelegates: [HomerPageDelegate] = [.continuationsChanged]
}

public enum HomerDispatchKind: HomerRecordKind {
	public static let noun = "dispatch"

	public static func page(
		_ client: HomerContinuationsClient,
		baseURL: String,
		query: HomerRecordQuery<HomerDispatchStatus>
	) async throws -> HomerRecordPage<HomerDispatch> {
		try await client.dispatches(baseURL, query)
	}

	public static func cancel(_ client: HomerContinuationsClient, baseURL: String, id: Int) async throws {
		try await client.cancelDispatch(baseURL, id)
	}

	/// In the console's words for cancelling a dispatch from its question.
	public static func cancelAlert(_ dispatch: HomerDispatch) -> (title: String, message: String, confirm: String, keep: String) {
		(
			"Cancel this dispatch?",
			"The question run #\(dispatch.originProcessId) asked expires, and \(dispatch.agentName) never starts. This cannot be undone.",
			"Yes, Cancel",
			"Keep Waiting"
		)
	}

	public static let notCancellableMessage =
		"This dispatch can no longer be cancelled — its question was already answered or cancelled."

	/// Its question expired with it: the open questions are re-read.
	public static let changedDelegates: [HomerPageDelegate] = [.questionsChanged]
}
