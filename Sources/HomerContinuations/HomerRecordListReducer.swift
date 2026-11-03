import ComposableArchitecture
import Foundation
import HomerCore

/// One of the Continuations page's two lists — continuations or ask-and-dispatches (`Kind`). By
/// default it shows what needs attention: the pending ones, soonest to expire first, and those that
/// failed to start their agent. The status filter turns it into the history — every status, or
/// one — and the agent filter keeps the records that start one agent; those lists are paged
/// (newest first) with Load More. A pending record can be cancelled.
@Reducer
public struct HomerRecordListReducer<Kind: HomerRecordKind>: Sendable {
	public typealias Record = Kind.Record
	public typealias Status = Record.Status

	/// The console's cadence for continuations (`useContinuations`): there is no event to listen to.
	package static var pollInterval: Duration {
		.seconds(30)
	}

	/// A history page, and what Load More adds — the server's default `limit`.
	package static var pageSize: Int {
		100
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public internal(set) var filter: HomerRecordFilter<Status> = .open
		/// Only the records that start this agent.
		public internal(set) var agentFilter: String?
		/// How many history rows are asked for; Load More grows it, so a refresh keeps every
		/// loaded row current.
		public internal(set) var limit = HomerRecordListReducer.pageSize

		/// The `open` view: the pending records, soonest to expire first, and how many there are
		/// past the page.
		public internal(set) var pending: IdentifiedArrayOf<Record> = []
		public internal(set) var pendingTotal = 0
		/// The `open` view: records that never started their agent. Agents report crashes through
		/// continuations, so a lost one is a report nobody gets — the console lists them for that
		/// reason.
		public internal(set) var failed: IdentifiedArrayOf<Record> = []
		/// Any other filter: one page, newest first, and how many match past it.
		public internal(set) var records: IdentifiedArrayOf<Record> = []
		public internal(set) var total = 0

		public internal(set) var hasLoaded = false
		/// The last refresh's failure; the last good lists stay on screen under it.
		public internal(set) var loadError: String?
		/// Cancel requests still waiting on the server.
		public internal(set) var cancellingIDs: Set<Record.ID> = []
		/// Why a cancel failed, shown on the record's card as the console does.
		public internal(set) var cancelErrors: [Record.ID: String] = [:]
		@Presents
		public var alert: AlertState<Action.Alert>?
		/// Between `shown` and `hidden`. An answer arriving outside it is dropped.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		/// Every record on screen, whichever the view.
		var shown: [Record] {
			filter == .open ? pending.elements + failed.elements : records.elements
		}

		/// History rows past the page, which Load More asks for.
		public var hasMore: Bool {
			filter != .open && records.count < total
		}
	}

	/// What one refresh read, for the filters it was asked with.
	public struct Lists: Equatable, Sendable {
		public var filter: HomerRecordFilter<Status>
		public var agentFilter: String?
		/// The `open` view: pending and failed; any other filter: `records`.
		public var pending: HomerRecordPage<Record>?
		public var failed: HomerRecordPage<Record>?
		public var records: HomerRecordPage<Record>?

		public init(
			filter: HomerRecordFilter<Status>,
			agentFilter: String? = nil,
			pending: HomerRecordPage<Record>? = nil,
			failed: HomerRecordPage<Record>? = nil,
			records: HomerRecordPage<Record>? = nil
		) {
			self.filter = filter
			self.agentFilter = agentFilter
			self.pending = pending
			self.failed = failed
			self.records = records
		}
	}

	public enum Action {
		/// The list came on screen; it polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case filterChanged(HomerRecordFilter<Status>)
		case agentFilterChanged(String?)
		case loadMoreTapped
		case delegate(HomerPageDelegate)

		case loaded(Result<Lists, any Error>)
		case processTapped(processId: Int)
		case cancelTapped(id: Record.ID)
		case cancelFinished(id: Record.ID, Result<Void, any Error>)
		case alert(PresentationAction<Alert>)

		public enum Alert: Equatable, Sendable {
			case cancelConfirmed(id: Record.ID)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case polling
	}

	@Dependency(HomerContinuationsClient.self)
	private var client

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .shown:
				state.isShown = true
				return poll(state)

			case .refreshTapped:
				return state.isShown ? poll(state) : .none

			case .hidden:
				state.isShown = false
				return .cancel(id: CancelID.polling)

			case let .filterChanged(filter):
				guard filter != state.filter else {
					return .none
				}
				state.filter = filter
				return refilter(&state)

			case let .agentFilterChanged(agentName):
				guard agentName != state.agentFilter else {
					return .none
				}
				state.agentFilter = agentName
				return refilter(&state)

			case .loadMoreTapped:
				guard state.hasMore else {
					return .none
				}
				state.limit += Self.pageSize
				return state.isShown ? poll(state) : .none

			case .delegate:
				return .none

			case let .loaded(.success(lists)):
				// An answer for filters since changed: the poll for the new ones is on its way.
				guard state.isShown, lists.filter == state.filter, lists.agentFilter == state.agentFilter else {
					return .none
				}
				if let pending = lists.pending {
					state.pending = Self.identified(HomerExpiry.soonestFirst(pending.items))
					state.pendingTotal = pending.total
				}
				if let failed = lists.failed {
					state.failed = Self.identified(failed.items)
				}
				if let records = lists.records {
					state.records = Self.identified(records.items)
					state.total = records.total
				}
				state.hasLoaded = true
				state.loadError = nil
				// A cancel error belongs to a card still offering Cancel.
				let cancellable = Set(state.shown.filter(\.isCancellable).map(\.id))
				state.cancelErrors = state.cancelErrors.filter { cancellable.contains($0.key) }
				return .none

			case let .loaded(.failure(error)):
				guard state.isShown else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = error.localizedDescription
				return .none

			case let .processTapped(processId):
				return .send(.delegate(.openProcess(processId: processId)))

			case let .cancelTapped(id):
				guard let record = state.shown.first(where: { $0.id == id }), record.isCancellable else {
					return .none
				}
				state.cancelErrors[id] = nil
				let words = Kind.cancelAlert(record)
				state.alert = AlertState {
					TextState(words.title)
				} actions: {
					ButtonState(role: .destructive, action: .cancelConfirmed(id: id)) {
						TextState(words.confirm)
					}
					ButtonState(role: .cancel) {
						TextState(words.keep)
					}
				} message: {
					TextState(words.message)
				}
				return .none

			case let .alert(.presented(.cancelConfirmed(id))):
				guard state.cancellingIDs.insert(id).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.cancelFinished(id: id, Result { try await Kind.cancel(client, baseURL: baseURL, id: id) }))
				}

			case .alert:
				return .none

			case let .cancelFinished(id, result):
				// Not waited on any more: the page's state was replaced (signed out) meanwhile.
				guard state.cancellingIDs.remove(id) != nil else {
					return .none
				}
				switch result {
				case .success:
					state.pending.remove(id: id)
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return .send(.delegate(.unauthorized))
					}
					state.cancelErrors[id] = Self.cancelErrorMessage(error)
				}
				// Either way the lists are refetched, as the console does on settle: a 409/404
				// means what is shown was stale. The instance's counts too.
				return .merge(
					.merge(Kind.changedDelegates.map { .send(.delegate($0)) }),
					state.isShown ? poll(state) : .none
				)
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}

	static func cancelErrorMessage(_ error: any Error) -> String {
		switch error as? HomerAPIError {
		case .conflict, .server(status: 404, _):
			Kind.notCancellableMessage
		default:
			error.localizedDescription
		}
	}

	private static func identified(_ records: [Record]) -> IdentifiedArrayOf<Record> {
		IdentifiedArray(records, uniquingIDsWith: { first, _ in first })
	}

	/// A filter changed: the history starts from its first page again, and what was shown for the
	/// old filters goes, so it is never read as the new ones' answer.
	private func refilter(_ state: inout State) -> Effect<Action> {
		state.limit = Self.pageSize
		state.pending = []
		state.pendingTotal = 0
		state.failed = []
		state.records = []
		state.total = 0
		state.hasLoaded = false
		state.loadError = nil
		return state.isShown ? poll(state) : .cancel(id: CancelID.polling)
	}

	/// Fetches the view's lists right away, then on the console's cadence. Restarting it replaces
	/// the running loop, so an older answer never lands after a newer one.
	private func poll(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, filter = state.filter, agentName = state.agentFilter, limit = state.limit] send in
			while true {
				await send(.loaded(Result {
					try await Self.fetch(client, baseURL: baseURL, filter: filter, agentName: agentName, limit: limit)
				}))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.polling, cancelInFlight: true)
	}

	private static func fetch(
		_ client: HomerContinuationsClient,
		baseURL: String,
		filter: HomerRecordFilter<Status>,
		agentName: String?,
		limit: Int
	) async throws -> Lists {
		switch filter {
		case .open:
			async let pending = Kind.page(client, baseURL: baseURL, query: HomerRecordQuery(status: .pending, agentName: agentName))
			async let failed = Kind.page(client, baseURL: baseURL, query: HomerRecordQuery(status: .failed, agentName: agentName))
			return try await Lists(filter: filter, agentFilter: agentName, pending: pending, failed: failed)
		case .all, .status:
			let records = try await Kind.page(
				client,
				baseURL: baseURL,
				query: HomerRecordQuery(status: filter.queriedStatus, agentName: agentName, limit: limit)
			)
			return Lists(filter: filter, agentFilter: agentName, records: records)
		}
	}
}
