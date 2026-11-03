import ComposableArchitecture
import Foundation
import HomerCore

public typealias HomerContinuationListReducer = HomerRecordListReducer<HomerContinuationKind>
public typealias HomerDispatchListReducer = HomerRecordListReducer<HomerDispatchKind>

/// The Continuations page of one instance (`app/(dashboard)/continuations/page.tsx`), and the
/// ask-and-dispatches beside them: two kinds of agent the server starts later on a run's behalf —
/// once a watched run finishes, or once a question is answered. Each is a list
/// (`HomerRecordListReducer`) of what needs attention by default, its history on a filter; the
/// section picker shows one at a time, and only that one polls. A card opens the record's detail.
@Reducer
public struct HomerContinuationsReducer: Sendable {
	/// The lists' cadence (`useContinuations`).
	package static let pollInterval = HomerContinuationListReducer.pollInterval

	public enum Section: CaseIterable, Equatable, Sendable {
		case continuations
		case dispatches

		public var title: String {
			switch self {
			case .continuations:
				"Continuations"
			case .dispatches:
				"Dispatches"
			}
		}
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public internal(set) var section: Section = .continuations
		public var continuations: HomerContinuationListReducer.State
		public var dispatches: HomerDispatchListReducer.State
		/// The agent filter's choices: the instance's agent names, which it keeps current.
		public var agentNames: [String] = []
		@Presents
		public var detail: HomerRecordDetailReducer.State?
		/// Between `shown` and `hidden`.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
			self.continuations = HomerContinuationListReducer.State(baseURL: baseURL)
			self.dispatches = HomerDispatchListReducer.State(baseURL: baseURL)
		}
	}

	public enum Action {
		/// The page came on screen; its section polls until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: the section on screen fetches right away.
		case refreshTapped
		case sectionChanged(Section)
		/// A card's click: its detail opens in a sheet.
		case recordTapped(HomerRecordDetailReducer.Record)
		case delegate(HomerPageDelegate)

		case continuations(HomerContinuationListReducer.Action)
		case dispatches(HomerDispatchListReducer.Action)
		case detail(PresentationAction<HomerRecordDetailReducer.Action>)
	}

	public init() {}

	public var body: some Reducer<State, Action> {
		Scope(\.continuations, action: \.continuations) {
			HomerContinuationListReducer()
		}
		Scope(\.dispatches, action: \.dispatches) {
			HomerDispatchListReducer()
		}
		Reduce { state, action in
			switch action {
			case .shown:
				state.isShown = true
				return show(state.section)

			case .hidden:
				state.isShown = false
				return hide(state.section)

			case .refreshTapped:
				guard state.isShown else {
					return .none
				}
				switch state.section {
				case .continuations:
					return .send(.continuations(.refreshTapped))
				case .dispatches:
					return .send(.dispatches(.refreshTapped))
				}

			case let .sectionChanged(section):
				guard section != state.section else {
					return .none
				}
				let previous = state.section
				state.section = section
				return state.isShown ? .merge(hide(previous), show(section)) : .none

			case let .recordTapped(record):
				state.detail = HomerRecordDetailReducer.State(baseURL: state.baseURL, record: record)
				return .none

			case let .continuations(.delegate(delegate)), let .dispatches(.delegate(delegate)):
				return .send(.delegate(delegate))

			case let .detail(.presented(.delegate(delegate))):
				switch delegate {
				case .unauthorized:
					return .send(.delegate(.unauthorized))
				case let .openProcess(processId):
					state.detail = nil
					return .send(.delegate(.openProcess(processId: processId)))
				case let .cancel(.continuation(continuation)):
					state.detail = nil
					return .send(.continuations(.cancelTapped(id: continuation.id)))
				case let .cancel(.dispatch(dispatch)):
					state.detail = nil
					return .send(.dispatches(.cancelTapped(id: dispatch.id)))
				}

			case .delegate, .continuations, .dispatches, .detail:
				return .none
			}
		}
		.ifLet(\.$detail, action: \.detail) {
			HomerRecordDetailReducer()
		}
	}

	private func show(_ section: Section) -> Effect<Action> {
		switch section {
		case .continuations:
			.send(.continuations(.shown))
		case .dispatches:
			.send(.dispatches(.shown))
		}
	}

	private func hide(_ section: Section) -> Effect<Action> {
		switch section {
		case .continuations:
			.send(.continuations(.hidden))
		case .dispatches:
			.send(.dispatches(.hidden))
		}
	}
}
