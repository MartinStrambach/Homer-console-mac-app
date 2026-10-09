import ComposableArchitecture
import Foundation
import HomerCore

/// The Agents and Schedules pages of one instance: both show the instance's agents, Schedules
/// only those with a cron. Agents mirrors the console's `agents/page.tsx` (search, Reload, the
/// agent cards, Run); Schedules its `schedules/page.tsx` (with its Run, which fires the cron
/// now). An agent's page (`HomerAgentDetailReducer`) and its editor (`HomerAgentEditorReducer`)
/// show in place of the page that opened them, and its workflow graph is also a sheet over the
/// cards. "New Agent" is a sheet whose agent opens in its editor.
@Reducer
public struct HomerAgentsReducer: Sendable {
	/// The console reads the list once and keeps it 5 minutes (`polling.agentsCacheTime`), then
	/// refetches when the server announces a reload on its `/stream/agents` events. A poll
	/// stands in for that stream here, as the process list's does for the status stream; it
	/// also keeps the schedules' next and last runs current once a cron has fired.
	static let pollInterval: Duration = .seconds(30)

	/// The two pages this reducer backs.
	public enum Page: Equatable, Sendable {
		case agents
		case schedules
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		/// By name, as the console sorts them.
		public internal(set) var agents: IdentifiedArrayOf<HomerAgent> = []
		public internal(set) var hasLoaded = false
		/// The last refresh's failure; the last good list stays on screen below it.
		public internal(set) var loadError: String?
		/// The console's search: agents whose name contains it, ignoring case.
		public var searchText = ""
		public internal(set) var isReloading = false
		public internal(set) var reloadResult: HomerAgentReloadResult?
		public internal(set) var reloadError: String?
		@Presents
		public var runAgent: HomerRunAgentReducer.State?
		@Presents
		public var workflowGraph: HomerAgentWorkflowGraphReducer.State?
		@Presents
		public var newAgent: HomerNewAgentReducer.State?
		/// An agent's page, shown in place of the page it was opened from. Plain optional state
		/// rather than `@Presents`: its run history polls, and only a plain cancellation ID can be
		/// stopped from here when the page is hidden or the whole state replaced (signed out).
		public var detail: HomerAgentDetailReducer.State?
		/// An agent's editor, shown in place of the page it was opened from — over the agent's
		/// page, if that opened it. Plain optional state, as `detail` is: its debug runs' output
		/// is followed until the run ends.
		public var editor: HomerAgentEditorReducer.State?
		/// Schedules whose "Run Now" is still waiting on the server.
		public internal(set) var cronRunsInFlight: Set<HomerAgent.ID> = []
		/// "Run Now"'s confirmation, and why a fire failed.
		@Presents
		public var alert: AlertState<Action.Alert>?
		/// The run the Run sheet started, opened once the sheet is gone — the run's page is a sheet
		/// too, and one sheet cannot come up while the other is still going.
		var processToOpen: Int?
		/// The page on screen, between `shown` and `hidden`: the list polls.
		var shownPage: Page?

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		var isShown: Bool {
			shownPage != nil
		}

		/// The Agents page's cards.
		public var filteredAgents: [HomerAgent] {
			let search = searchText.lowercased()
			guard !search.isEmpty else {
				return Array(agents)
			}
			return agents.filter { $0.name.lowercased().contains(search) }
		}

		/// The Schedules page's rows.
		public var schedules: [HomerAgent] {
			HomerAgent.schedules(agents)
		}

		/// What the editor's Back returns to: the agent's page under it, or the page it was
		/// opened from.
		var editorBackTitle: String {
			if let detail, detail.openedFrom == editor?.openedFrom {
				return detail.agentName
			}
			return editor?.openedFrom == .schedules ? "Schedules" : "Agents"
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// One of the pages came on screen; the list polls until `hidden`.
		case shown(Page)
		case hidden
		/// The header's Refresh: fetches right away, without waiting for the next poll.
		case refreshTapped
		case agentsLoaded(Result<[HomerAgent], any Error>)

		case reloadTapped
		case reloadFinished(Result<HomerAgentReloadResult, any Error>)
		case reloadResultDismissed
		case reloadErrorDismissed

		case runTapped(agentName: String)
		case runAgent(PresentationAction<HomerRunAgentReducer.Action>)
		/// The Run sheet went off screen, however it was closed.
		case runSheetDismissed

		/// The agent's page: its run history, parameters and workflow graph.
		case agentTapped(agentName: String)
		case detail(HomerAgentDetailReducer.Action)
		case workflowGraphTapped(agentName: String)
		case workflowGraph(PresentationAction<HomerAgentWorkflowGraphReducer.Action>)
		/// The agent's editor: its files and debug runs.
		case editTapped(agentName: String)
		case editor(HomerAgentEditorReducer.Action)
		/// The New Agent sheet; the agent it creates opens in its editor.
		case newAgentTapped
		case newAgent(PresentationAction<HomerNewAgentReducer.Action>)
		case processTapped(processId: Int)

		/// The Schedules page's Run: fires the agent now as its cron would, once confirmed.
		case cronRunTapped(agentName: String)
		case cronRunFinished(agentName: String, Result<Void, any Error>)
		case alert(PresentationAction<Alert>)

		case delegate(HomerPageDelegate)

		public enum Alert: Equatable, Sendable {
			case cronRunConfirmed(agentName: String)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case polling
	}

	@Dependency(HomerAgentsClient.self)
	private var agentsClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case let .shown(page):
				state.shownPage = page
				let debugTails: Effect<Action> = state.editor?.debug.activeRun != nil ? .send(.editor(.debug(.resumeTails))) : .none
				return .merge(poll(state), showDetailIfOnScreen(state), debugTails)

			case .refreshTapped:
				guard state.isShown else {
					return .none
				}
				if state.editor?.openedFrom == state.shownPage {
					return .merge(poll(state), .send(.editor(.refreshTapped)))
				}
				let detail: Effect<Action> = state.detail?.isShown == true ? .send(.detail(.refreshTapped)) : .none
				return .merge(poll(state), detail)

			case .hidden:
				state.shownPage = nil
				state.detail?.isShown = false
				// The debug runs' output is followed again when a page comes back.
				state.editor?.debug.pauseTails()
				return .merge(
					.cancel(id: CancelID.polling),
					.cancel(id: HomerAgentDetailReducer.CancelID.polling),
					HomerAgentDebugReducer.cancelTails(),
					// With no page left (the state was replaced), whatever else it runs stops too.
					state.detail == nil ? HomerAgentDetailReducer.cancelEffects() : .none,
					state.editor == nil ? HomerAgentEditorReducer.cancelEffects() : .none
				)

			case let .agentsLoaded(.success(agents)):
				let sorted = agents.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
				state.agents = IdentifiedArray(sorted, uniquingIDsWith: { first, _ in first })
				if let agentName = state.detail?.agentName {
					let agent = state.agents[id: agentName]
					state.detail?.agent = agent
				}
				if let agentName = state.editor?.agentName {
					let agent = state.agents[id: agentName]
					state.editor?.update(agent: agent)
				}
				state.hasLoaded = true
				state.loadError = nil
				return .none

			case let .agentsLoaded(.failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.loadError = error.localizedDescription
				return .none

			case .reloadTapped:
				guard !state.isReloading else {
					return .none
				}
				state.isReloading = true
				state.reloadResult = nil
				state.reloadError = nil
				return .run { [baseURL = state.baseURL] send in
					await send(.reloadFinished(Result { try await agentsClient.reload(baseURL) }))
				}

			case let .reloadFinished(result):
				// A reload of a user since signed out lands in a state that never started it.
				guard state.isReloading else {
					return .none
				}
				state.isReloading = false
				switch result {
				case let .success(reloadResult):
					state.reloadResult = reloadResult
					// The console refetches the list after a reload.
					return state.isShown ? poll(state) : .none
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return .send(.delegate(.unauthorized))
					}
					state.reloadError = error.localizedDescription
					return .none
				}

			case .reloadResultDismissed:
				state.reloadResult = nil
				return .none

			case .reloadErrorDismissed:
				state.reloadError = nil
				return .none

			case let .runTapped(agentName):
				guard let agent = state.agents[id: agentName] else {
					return .none
				}
				state.processToOpen = nil
				state.runAgent = HomerRunAgentReducer.State(baseURL: state.baseURL, agent: agent)
				return .none

			case let .runAgent(.presented(.delegate(.started(processId)))):
				state.runAgent = nil
				state.processToOpen = processId
				return .none

			case .runAgent(.presented(.delegate(.unauthorized))):
				state.runAgent = nil
				return .send(.delegate(.unauthorized))

			case .runAgent:
				return .none

			case .runSheetDismissed:
				guard let processId = state.processToOpen else {
					return .none
				}
				state.processToOpen = nil
				// The console takes you to the new run.
				return .send(.processTapped(processId: processId))

			case let .agentTapped(agentName):
				state.detail = HomerAgentDetailReducer.State(
					baseURL: state.baseURL,
					agentName: agentName,
					openedFrom: state.shownPage ?? .agents,
					agent: state.agents[id: agentName]
				)
				// Another agent's page may have been polling.
				return .merge(HomerAgentDetailReducer.cancelEffects(), showDetailIfOnScreen(state))

			case .detail(.delegate(.back)):
				state.detail = nil
				return HomerAgentDetailReducer.cancelEffects()

			case .detail(.delegate(.run)):
				guard let agentName = state.detail?.agentName else {
					return .none
				}
				return .send(.runTapped(agentName: agentName))

			case .detail(.delegate(.edit)):
				guard let agentName = state.detail?.agentName else {
					return .none
				}
				return .send(.editTapped(agentName: agentName))

			case let .detail(.delegate(.openProcess(processId))):
				return .send(.processTapped(processId: processId))

			case .detail(.delegate(.unauthorized)):
				return .send(.delegate(.unauthorized))

			case .detail:
				return .none

			case let .workflowGraphTapped(agentName):
				state.workflowGraph = HomerAgentWorkflowGraphReducer.State(baseURL: state.baseURL, agentName: agentName)
				return .none

			case .workflowGraph(.presented(.delegate(.unauthorized))):
				state.workflowGraph = nil
				return .send(.delegate(.unauthorized))

			case .workflowGraph:
				return .none

			case let .editTapped(agentName):
				state.editor = HomerAgentEditorReducer.State(
					baseURL: state.baseURL,
					agentName: agentName,
					openedFrom: state.shownPage ?? .agents,
					agent: state.agents[id: agentName]
				)
				// The agent's page under it stops polling until the editor goes.
				var hideDetail: Effect<Action> = .none
				if state.detail?.isShown == true, state.detail?.openedFrom == state.editor?.openedFrom {
					state.detail?.isShown = false
					hideDetail = .cancel(id: HomerAgentDetailReducer.CancelID.polling)
				}
				// Another agent's editor may have been following a debug run.
				return .concatenate(
					HomerAgentEditorReducer.cancelEffects(),
					hideDetail,
					.send(.editor(.start))
				)

			case .editor(.delegate(.back)):
				state.editor = nil
				return .merge(HomerAgentEditorReducer.cancelEffects(), showDetailIfOnScreen(state))

			case .editor(.delegate(.filesChanged)):
				// The server reloaded the agent; the list shows its new definition.
				return state.isShown ? poll(state) : .none

			case let .editor(.delegate(.openProcess(processId))):
				return .send(.processTapped(processId: processId))

			case .editor(.delegate(.unauthorized)):
				return .send(.delegate(.unauthorized))

			case .editor:
				return .none

			case .newAgentTapped:
				state.newAgent = HomerNewAgentReducer.State(baseURL: state.baseURL)
				return .none

			case let .newAgent(.presented(.delegate(.created(agentName)))):
				state.newAgent = nil
				// The editor finds the agent in the list once it is read again: the server loaded
				// it on creation.
				return .concatenate(
					.send(.editTapped(agentName: agentName)),
					state.isShown ? poll(state) : .none
				)

			case .newAgent(.presented(.delegate(.unauthorized))):
				state.newAgent = nil
				return .send(.delegate(.unauthorized))

			case .newAgent:
				return .none

			case let .processTapped(processId):
				return .send(.delegate(.openProcess(processId: processId)))

			case let .cronRunTapped(agentName):
				guard !state.cronRunsInFlight.contains(agentName) else {
					return .none
				}
				// The console's own warning: nothing comes back to say the run did not start.
				state.alert = AlertState {
					TextState("Run \(agentName) now?")
				} actions: {
					ButtonState(action: .cronRunConfirmed(agentName: agentName)) {
						TextState("Run Now")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState(
						"This starts the agent immediately with its cron semantics — no parameters are asked for, and the run is owned by the scheduler. A fire that starts no run (cost cap, cooldown, lock, parallel-run or queued-runs cap) is only logged, never reported as an error."
					)
				}
				return .none

			case let .alert(.presented(.cronRunConfirmed(agentName))):
				guard state.cronRunsInFlight.insert(agentName).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.cronRunFinished(
						agentName: agentName,
						Result { try await agentsClient.fireCron(baseURL, agentName) }
					))
				}

			case .alert:
				return .none

			case let .cronRunFinished(agentName, result):
				// Not waited on any more: the page's state was replaced (signed out) meanwhile.
				guard state.cronRunsInFlight.remove(agentName) != nil else {
					return .none
				}
				switch result {
				case .success:
					// The fire records the run as the schedule's last one; the console refetches
					// the list to show it.
					return state.isShown ? poll(state) : .none
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return .send(.delegate(.unauthorized))
					}
					state.alert = AlertState {
						TextState("Could not run \(agentName)")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(Self.cronRunErrorMessage(error, agentName: agentName))
					}
					return .none
				}

			case .delegate:
				return .none
			}
		}
		.ifLet(\.detail, action: \.detail) {
			HomerAgentDetailReducer()
		}
		.ifLet(\.editor, action: \.editor) {
			HomerAgentEditorReducer()
		}
		.ifLet(\.$runAgent, action: \.runAgent) {
			HomerRunAgentReducer()
		}
		.ifLet(\.$workflowGraph, action: \.workflowGraph) {
			HomerAgentWorkflowGraphReducer()
		}
		.ifLet(\.$newAgent, action: \.newAgent) {
			HomerNewAgentReducer()
		}
		.ifLet(\.$alert, action: \.alert)
	}

	/// The server answers a non-admin with the 404 of an unknown agent, so the two cannot be told
	/// apart.
	static func cronRunErrorMessage(_ error: any Error, agentName: String) -> String {
		if case .server(status: 404, _) = error as? HomerAPIError {
			return "\(agentName) is no longer loaded, or your account may not run schedules."
		}
		return error.localizedDescription
	}

	/// Starts the agent's page if it belongs to the page now on screen, is not covered by the
	/// editor and is not running yet.
	private func showDetailIfOnScreen(_ state: State) -> Effect<Action> {
		guard let detail = state.detail,
		      !detail.isShown,
		      detail.openedFrom == state.shownPage,
		      state.editor?.openedFrom != state.shownPage
		else {
			return .none
		}
		return .send(.detail(.shown))
	}

	/// Fetches right away, then every `pollInterval`. Restarting it replaces the running loop.
	private func poll(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.agentsLoaded(Result { try await agentsClient.agents(baseURL) }))
				try await clock.sleep(for: Self.pollInterval)
			}
		}
		.cancellable(id: CancelID.polling, cancelInFlight: true)
	}
}
