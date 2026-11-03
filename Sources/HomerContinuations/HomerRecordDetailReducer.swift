import ComposableArchitecture
import Foundation
import HomerCore

/// A continuation's or a dispatch's detail, in a sheet over the Continuations page: everything the
/// server keeps of it — the inputs it starts the agent with, its times, the runs around it — read
/// again (`GET /continuations/{id}`, `/dispatches/{id}`) when the sheet opens, the card's copy
/// standing in until then.
@Reducer
public struct HomerRecordDetailReducer: Sendable {
	/// The record the sheet shows.
	public enum Record: Equatable, Sendable {
		case continuation(HomerContinuation)
		case dispatch(HomerDispatch)

		/// What tells two records apart, across the two kinds.
		public var key: String {
			switch self {
			case let .continuation(continuation):
				"continuation-\(continuation.id)"
			case let .dispatch(dispatch):
				"dispatch-\(dispatch.id)"
			}
		}

		var isCancellable: Bool {
			switch self {
			case let .continuation(continuation):
				continuation.isCancellable
			case let .dispatch(dispatch):
				dispatch.isCancellable
			}
		}
	}

	@ObservableState
	public struct State: Equatable, Identifiable {
		public let baseURL: String
		public internal(set) var record: Record
		public internal(set) var isLoading = false
		/// Why the fresh read failed; the card's copy stays on screen under it.
		public internal(set) var loadError: String?

		public init(baseURL: String, record: Record) {
			self.baseURL = baseURL
			self.record = record
		}

		public var id: String {
			record.key
		}
	}

	public enum Action {
		case task
		case loaded(Result<Record, any Error>)
		/// A run of the record's — the one that asked, the one it waits for, the one it started.
		case processTapped(processId: Int)
		case cancelTapped
		case delegate(Delegate)

		public enum Delegate: Equatable, Sendable {
			case unauthorized
			/// The sheet closes and the run's page opens.
			case openProcess(processId: Int)
			/// The sheet closes and the list asks before cancelling.
			case cancel(Record)
		}
	}

	@Dependency(HomerContinuationsClient.self)
	private var client

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .task:
				state.isLoading = true
				return .run { [baseURL = state.baseURL, record = state.record] send in
					await send(.loaded(Result {
						switch record {
						case let .continuation(continuation):
							try await .continuation(client.continuation(baseURL, continuation.id))
						case let .dispatch(dispatch):
							try await .dispatch(client.dispatch(baseURL, dispatch.id))
						}
					}))
				}

			case let .loaded(.success(record)):
				state.isLoading = false
				state.loadError = nil
				state.record = record
				return .none

			case let .loaded(.failure(error)):
				state.isLoading = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = error.localizedDescription
				return .none

			case let .processTapped(processId):
				return .send(.delegate(.openProcess(processId: processId)))

			case .cancelTapped:
				guard state.record.isCancellable else {
					return .none
				}
				return .send(.delegate(.cancel(state.record)))

			case .delegate:
				return .none
			}
		}
	}
}
