import ComposableArchitecture
import Foundation
import HomerCore

/// The Runners page of one instance (admins only), the console's
/// `app/(dashboard)/runners/page.tsx`: the configured runners, the external runners' registered
/// instances and the runs waiting for a runner, each polled on the console's 5 s.
@Reducer
public struct HomerRunnersReducer: Sendable {
	/// `useRunners`' and `useRunnerQueue`'s `refetchInterval`.
	static let pollInterval: Duration = .seconds(5)

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String

		public internal(set) var runners: HomerRunners?
		public internal(set) var runnersError: String?

		public internal(set) var queue: HomerRunnerQueue?
		public internal(set) var queueError: String?

		/// Between `shown` and `hidden`: the page polls.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		/// Nothing has answered yet, successfully or not.
		public var isLoading: Bool {
			runners == nil && queue == nil && runnersError == nil && queueError == nil
		}

		/// The failed refreshes' messages, each once: an unreachable server fails both calls with
		/// the same one.
		public var errorMessages: [String] {
			var seen = Set<String>()
			return [runnersError, queueError].compactMap(\.self).filter { seen.insert($0).inserted }
		}
	}

	public enum Action {
		/// The page came on screen; it polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case runnersLoaded(Result<HomerRunners, any Error>)
		case queueLoaded(Result<HomerRunnerQueue, any Error>)
		case delegate(HomerPageDelegate)
	}

	private nonisolated enum CancelID: Hashable {
		case runnersPolling
		case queuePolling
	}

	@Dependency(HomerRunnersClient.self)
	private var runnersClient

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
				return .merge(pollRunners(state), pollQueue(state))

			case .refreshTapped:
				return state.isShown ? .merge(pollRunners(state), pollQueue(state)) : .none

			case .hidden:
				state.isShown = false
				return stopPolling()

			case let .runnersLoaded(.success(runners)):
				state.runners = runners
				state.runnersError = nil
				return .none

			case let .runnersLoaded(.failure(error)):
				return failed(error, at: \.runnersError, &state)

			case let .queueLoaded(.success(queue)):
				state.queue = queue
				state.queueError = nil
				return .none

			case let .queueLoaded(.failure(error)):
				return failed(error, at: \.queueError, &state)

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
			return .merge(stopPolling(), .send(.delegate(.unauthorized)))
		}
		state[keyPath: message] = error.localizedDescription
		return .none
	}

	private func stopPolling() -> Effect<Action> {
		.merge(.cancel(id: CancelID.runnersPolling), .cancel(id: CancelID.queuePolling))
	}

	private func pollRunners(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.runnersLoaded(Result { try await runnersClient.runners(baseURL) }))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.runnersPolling, cancelInFlight: true)
	}

	private func pollQueue(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.queueLoaded(Result { try await runnersClient.queue(baseURL) }))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.queuePolling, cancelInFlight: true)
	}
}
