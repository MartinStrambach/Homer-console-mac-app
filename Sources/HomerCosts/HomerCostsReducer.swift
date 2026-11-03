import ComposableArchitecture
import Foundation
import HomerCore

/// The Costs page of one instance (admins only), the console's `app/(dashboard)/costs/page.tsx`:
/// rolling-window spend against the configured caps, polled on the console's 5 s; and the
/// persistent ledger's month (with its month picker) and all-time totals, and the spend per value
/// of one cost-tracked tag key, re-read every 30 s, the console's `staleTime` for them.
@Reducer
public struct HomerCostsReducer: Sendable {
	/// `useCosts`' `refetchInterval`.
	static let snapshotPollInterval: Duration = .seconds(5)
	/// `useMonthlyCosts`/`useTotalCosts`' `staleTime`. The console re-reads stale ledger data
	/// when the page mounts or the window regains focus; a page left open here refreshes on it.
	static let ledgerPollInterval: Duration = .seconds(30)

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String

		public internal(set) var snapshot: HomerCostSnapshot?
		public internal(set) var snapshotError: String?

		/// The month the picker chose, `YYYY-MM`; nil follows the server's current UTC month,
		/// into the next one when it turns.
		public internal(set) var selectedMonth: String?
		/// The last month read. While another month loads it stays on screen, dimmed, as the
		/// console keeps its previous data.
		public internal(set) var monthly: HomerMonthlyCosts?
		public internal(set) var monthlyError: String?

		public internal(set) var totals: HomerTotalCosts?
		public internal(set) var totalsError: String?

		/// The tag key the picker chose; nil, or a key the server no longer tracks, follows the
		/// first tracked one (`shownTagKey`).
		public internal(set) var selectedTagKey: String?
		/// The last key's breakdown read. While another key loads it stays on screen, dimmed.
		public internal(set) var tagCosts: HomerCostByTag?
		public internal(set) var tagCostsError: String?
		/// The key the running loop reads; nil while none runs.
		var polledTagKey: String?

		/// Between `shown` and `hidden`: the page polls.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		/// Whether `monthly` is the month the picker shows.
		public var isMonthlyCurrent: Bool {
			guard let monthly else {
				return false
			}
			return selectedMonth == nil || monthly.month == selectedMonth
		}

		/// The picker's choice: the month asked for, else the one the server answered with.
		public var shownMonth: String? {
			selectedMonth ?? monthly?.month
		}

		/// The picker's months, newest first.
		public var monthChoices: [String] {
			var months = Set(monthly?.pickerMonths ?? [])
			if let selectedMonth {
				months.insert(selectedMonth)
			}
			return months.sorted(by: >)
		}

		/// The tag keys the server sums spend for, from the snapshot; none hides the card.
		public var tagKeys: [String] {
			snapshot?.costTrackedTagKeys ?? []
		}

		/// The picker's choice, as the console derives it: the key picked while the server still
		/// tracks it, else the first one.
		public var shownTagKey: String? {
			if let selectedTagKey, tagKeys.contains(selectedTagKey) {
				return selectedTagKey
			}
			return tagKeys.first
		}

		/// Whether `tagCosts` is the key the picker shows.
		public var isTagCostsCurrent: Bool {
			tagCosts != nil && tagCosts?.key == shownTagKey
		}

		/// Nothing has answered yet, successfully or not.
		public var isLoading: Bool {
			snapshot == nil && monthly == nil && totals == nil
				&& snapshotError == nil && monthlyError == nil && totalsError == nil
		}

		/// The failed refreshes' messages, each once: an unreachable server fails all three calls
		/// with the same one.
		public var errorMessages: [String] {
			var seen = Set<String>()
			return [snapshotError, monthlyError, totalsError, tagCostsError].compactMap(\.self).filter { seen.insert($0).inserted }
		}
	}

	public enum Action {
		/// The page came on screen; it polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case monthSelected(String)
		case tagKeySelected(String)
		case snapshotLoaded(Result<HomerCostSnapshot, any Error>)
		/// `month` is the one asked for (nil: the current one).
		case monthlyLoaded(month: String?, Result<HomerMonthlyCosts, any Error>)
		case totalsLoaded(Result<HomerTotalCosts, any Error>)
		/// `key` is the one asked for.
		case tagCostsLoaded(key: String, Result<HomerCostByTag, any Error>)
		case delegate(HomerPageDelegate)
	}

	private nonisolated enum CancelID: Hashable {
		case snapshotPolling
		case monthlyPolling
		case totalsPolling
		case tagCostsPolling
	}

	@Dependency(HomerCostsClient.self)
	private var costsClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .shown:
				guard !state.isShown else {
					return .none
				}
				state.isShown = true
				// With an earlier snapshot the key is known already; otherwise its arrival starts
				// the tag loop.
				return .merge(pollSnapshot(state), pollMonthly(state), pollTotals(state), syncTagPolling(&state))

			case .refreshTapped:
				guard state.isShown else {
					return .none
				}
				return .merge(
					pollSnapshot(state),
					pollMonthly(state),
					pollTotals(state),
					state.polledTagKey.map { pollTagCosts(baseURL: state.baseURL, key: $0) } ?? .none
				)

			case .hidden:
				state.isShown = false
				state.polledTagKey = nil
				return stopPolling()

			case let .monthSelected(month):
				guard month != state.shownMonth else {
					return .none
				}
				state.selectedMonth = month
				state.monthlyError = nil
				// Replaces the running loop, so the previous month's answer never lands after
				// this one's.
				return state.isShown ? pollMonthly(state) : .none

			case let .snapshotLoaded(.success(snapshot)):
				state.snapshot = snapshot
				state.snapshotError = nil
				// The tracked keys can change with a config reload.
				return syncTagPolling(&state)

			case let .tagKeySelected(key):
				guard key != state.shownTagKey else {
					return .none
				}
				state.selectedTagKey = key
				state.tagCostsError = nil
				return syncTagPolling(&state)

			case let .tagCostsLoaded(key, result):
				// A replaced loop's answer is dropped before it gets here; this also drops one
				// that was already in flight.
				guard key == state.polledTagKey else {
					return .none
				}
				switch result {
				case let .success(tagCosts):
					state.tagCosts = tagCosts
					state.tagCostsError = nil
					return .none
				case let .failure(error):
					return failed(error, at: \.tagCostsError, &state)
				}

			case let .snapshotLoaded(.failure(error)):
				return failed(error, at: \.snapshotError, &state)

			case let .monthlyLoaded(month, result):
				// Belt and braces: a month's loop is replaced when another is picked, so its
				// answer is dropped before it gets here anyway.
				guard month == state.selectedMonth else {
					return .none
				}
				switch result {
				case let .success(monthly):
					state.monthly = monthly
					state.monthlyError = nil
					return .none
				case let .failure(error):
					return failed(error, at: \.monthlyError, &state)
				}

			case let .totalsLoaded(.success(totals)):
				state.totals = totals
				state.totalsError = nil
				return .none

			case let .totalsLoaded(.failure(error)):
				return failed(error, at: \.totalsError, &state)

			case .delegate:
				return .none
			}
		}
	}

	/// A 401 is the instance's session ending: it signs out and replaces this state. Anything
	/// else is said above the last good data, which stays.
	private func failed(
		_ error: any Error,
		at message: WritableKeyPath<State, String?>,
		_ state: inout State
	) -> Effect<Action> {
		if error as? HomerAPIError == .unauthorized {
			state.isShown = false
			state.polledTagKey = nil
			return .merge(stopPolling(), .send(.delegate(.unauthorized)))
		}
		state[keyPath: message] = error.localizedDescription
		return .none
	}

	private func stopPolling() -> Effect<Action> {
		.merge(
			.cancel(id: CancelID.snapshotPolling),
			.cancel(id: CancelID.monthlyPolling),
			.cancel(id: CancelID.totalsPolling),
			.cancel(id: CancelID.tagCostsPolling)
		)
	}

	/// Points the tag loop at the key the picker shows, while the page is shown: starts it, moves
	/// it to another key, or stops it once the server tracks none.
	private func syncTagPolling(_ state: inout State) -> Effect<Action> {
		guard state.isShown, state.shownTagKey != state.polledTagKey else {
			return .none
		}
		state.polledTagKey = state.shownTagKey
		guard let key = state.polledTagKey else {
			state.tagCosts = nil
			state.tagCostsError = nil
			return .cancel(id: CancelID.tagCostsPolling)
		}
		return pollTagCosts(baseURL: state.baseURL, key: key)
	}

	private func pollTagCosts(baseURL: String, key: String) -> Effect<Action> {
		.run { send in
			while true {
				await send(.tagCostsLoaded(key: key, Result { try await costsClient.byTag(baseURL, key) }))
				try await clock.sleep(for: Self.ledgerPollInterval)
			}
		}
		.cancellable(id: CancelID.tagCostsPolling, cancelInFlight: true)
	}

	private func pollSnapshot(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.snapshotLoaded(Result { try await costsClient.snapshot(baseURL) }))
				try await clock.sleep(for: Self.snapshotPollInterval)
			}
		}
		.cancellable(id: CancelID.snapshotPolling, cancelInFlight: true)
	}

	private func pollMonthly(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, month = state.selectedMonth] send in
			while true {
				await send(.monthlyLoaded(month: month, Result { try await costsClient.monthly(baseURL, month) }))
				try await clock.sleep(for: Self.ledgerPollInterval)
			}
		}
		.cancellable(id: CancelID.monthlyPolling, cancelInFlight: true)
	}

	private func pollTotals(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.totalsLoaded(Result { try await costsClient.totals(baseURL) }))
				try await clock.sleep(for: Self.ledgerPollInterval)
			}
		}
		.cancellable(id: CancelID.totalsPolling, cancelInFlight: true)
	}
}
