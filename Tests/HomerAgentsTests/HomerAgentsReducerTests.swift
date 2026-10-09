import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerCore
@testable import HomerAgents
import Testing

@MainActor
@Suite("Homer agents page", .dependencies)
struct HomerAgentsReducerTests {
	private nonisolated static let baseURL = "https://homer.example.com"
	private let factory = HomerAgent(
		name: "factory",
		inputs: [
			HomerAgent.Input(paramName: "ticket", envName: "TICKET"),
			HomerAgent.Input(paramName: "dryRun", source: .header, required: false),
		],
		scriptCount: 3
	)
	private let nightly = HomerAgent(
		name: "Nightly",
		cron: HomerAgent.Cron(expression: "0 3 * * *", timezone: "UTC", nextRunAt: 1_760_000_000)
	)

	private func loadedState() -> HomerAgentsReducer.State {
		var state = HomerAgentsReducer.State(baseURL: Self.baseURL)
		state.agents = [factory, nightly]
		state.hasLoaded = true
		state.shownPage = .agents
		return state
	}

	@Test("coming on screen loads the agents, sorted by name, and polls until hidden")
	func pollsWhileShown() async {
		let clock = TestClock()
		let calls = LockIsolated(0)
		let store = TestStore(initialState: HomerAgentsReducer.State(baseURL: Self.baseURL)) {
			HomerAgentsReducer()
		} withDependencies: { [factory, nightly] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].agents = { baseURL in
				#expect(baseURL == Self.baseURL)
				calls.withValue { $0 += 1 }
				return [nightly, factory]
			}
		}

		await store.send(.shown(.agents)) {
			$0.shownPage = .agents
		}
		await store.receive(\.agentsLoaded) {
			$0.agents = [factory, nightly]
			$0.hasLoaded = true
		}
		await clock.advance(by: HomerAgentsReducer.pollInterval)
		await store.receive(\.agentsLoaded)

		await store.send(.hidden) {
			$0.shownPage = nil
		}
		await clock.advance(by: HomerAgentsReducer.pollInterval * 3)
		#expect(calls.value == 2)
	}

	@Test("a failed refresh keeps the last list on screen and says why; the next one clears it")
	func failedRefresh() async {
		let clock = TestClock()
		let fails = LockIsolated(true)
		let store = TestStore(initialState: loadedState()) {
			HomerAgentsReducer()
		} withDependencies: { [factory] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].agents = { _ in
				if fails.value {
					throw HomerAPIError.unreachable("offline")
				}
				return [factory]
			}
		}

		await store.send(.shown(.agents))
		await store.receive(\.agentsLoaded) {
			$0.loadError = HomerAPIError.unreachable("offline").localizedDescription
		}
		fails.setValue(false)
		await clock.advance(by: HomerAgentsReducer.pollInterval)
		await store.receive(\.agentsLoaded) {
			$0.agents = [factory]
			$0.loadError = nil
		}
		await store.send(.hidden) {
			$0.shownPage = nil
		}
	}

	@Test("a 401 asks the instance to sign out")
	func unauthorized() async {
		let store = TestStore(initialState: HomerAgentsReducer.State(baseURL: Self.baseURL)) {
			HomerAgentsReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerAgentsClient.self].agents = { _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.shown(.agents)) {
			$0.shownPage = .agents
		}
		await store.receive(\.agentsLoaded)
		await store.receive(\.delegate, .unauthorized)
		// What the instance does on that: hides the page, which stops the poll.
		await store.send(.hidden) {
			$0.shownPage = nil
		}
	}

	@Test("the search matches agent names, ignoring case")
	func search() {
		var state = loadedState()
		state.searchText = "NIGHT"
		#expect(state.filteredAgents == [nightly])
		state.searchText = ""
		#expect(state.filteredAgents == [factory, nightly])
		#expect(state.schedules == [nightly])
	}

	@Test("Reload shows what changed and reads the list again")
	func reload() async {
		let clock = TestClock()
		let result = HomerAgentReloadResult(added: ["factory"], errors: ["bad/agent.yaml: invalid"])
		var initialState = loadedState()
		initialState.reloadError = "earlier failure"
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		} withDependencies: { [factory] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].reload = { _ in result }
			$0[HomerAgentsClient.self].agents = { _ in [factory] }
		}

		await store.send(.reloadTapped) {
			$0.isReloading = true
			$0.reloadError = nil
		}
		await store.receive(\.reloadFinished) {
			$0.isReloading = false
			$0.reloadResult = result
		}
		await store.receive(\.agentsLoaded) {
			$0.agents = [factory]
		}
		await store.send(.reloadResultDismissed) {
			$0.reloadResult = nil
		}
		await store.send(.hidden) {
			$0.shownPage = nil
		}
	}

	@Test("a refused reload says why")
	func reloadFails() async {
		let store = TestStore(initialState: loadedState()) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].reload = { _ in throw HomerAPIError.forbidden }
		}

		await store.send(.reloadTapped) {
			$0.isReloading = true
		}
		await store.receive(\.reloadFinished) {
			$0.isReloading = false
			$0.reloadError = HomerAPIError.forbidden.localizedDescription
		}
	}

	@Test("Run checks the fields, starts the run and opens it once the sheet is gone")
	func runOpensNewRun() async {
		let sent = LockIsolated<(String, HomerAgentRunRequest)?>(nil)
		let store = TestStore(initialState: loadedState()) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].run = { baseURL, name, request in
				#expect(baseURL == Self.baseURL)
				sent.setValue((name, request))
				return 43
			}
		}

		await store.send(.runTapped(agentName: "factory")) {
			$0.runAgent = HomerRunAgentReducer.State(baseURL: Self.baseURL, agent: factory)
		}
		await store.send(.runAgent(.presented(.runTapped))) {
			$0.runAgent?.errors = ["ticket": "This field is required"]
		}
		await store.send(.runAgent(.presented(.valueChanged(paramName: "ticket", value: "MOB 1")))) {
			$0.runAgent?.values["ticket"] = "MOB 1"
			$0.runAgent?.errors = ["ticket": "String values cannot contain spaces"]
		}
		#expect(store.state.runAgent?.canRun == false)
		await store.send(.runAgent(.presented(.valueChanged(paramName: "ticket", value: "MOB-1")))) {
			$0.runAgent?.values["ticket"] = "MOB-1"
			$0.runAgent?.errors = [:]
		}
		#expect(store.state.runAgent?.canRun == true)

		await store.send(.runAgent(.presented(.runTapped))) {
			$0.runAgent?.isRunning = true
		}
		await store.receive(\.runAgent.runFinished) {
			$0.runAgent?.isRunning = false
		}
		await store.receive(\.runAgent.delegate.started) {
			$0.runAgent = nil
			$0.processToOpen = 43
		}
		// The sheet's `onDismiss`.
		await store.send(.runSheetDismissed) {
			$0.processToOpen = nil
		}
		await store.receive(\.processTapped)
		await store.receive(\.delegate, .openProcess(processId: 43))

		#expect(sent.value?.0 == "factory")
		#expect(sent.value?.1 == HomerAgentRunRequest(queryItems: [URLQueryItem(name: "ticket", value: "MOB-1")]))
	}

	@Test("a refused run stays in the sheet and says why")
	func runFails() async {
		var initialState = loadedState()
		initialState.runAgent = HomerRunAgentReducer.State(baseURL: Self.baseURL, agent: nightly)
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].run = { _, _, _ in
				throw HomerAPIError.server(status: 429, message: "Agent 'Nightly' is cooling down")
			}
		}

		await store.send(.runAgent(.presented(.runTapped))) {
			$0.runAgent?.isRunning = true
		}
		await store.receive(\.runAgent.runFinished) {
			$0.runAgent?.isRunning = false
			$0.runAgent?.runError = "Agent 'Nightly' is cooling down"
		}
	}

	@Test("a run that answers 401 closes the sheet and asks the instance to sign out")
	func runUnauthorized() async {
		var initialState = loadedState()
		initialState.runAgent = HomerRunAgentReducer.State(baseURL: Self.baseURL, agent: nightly)
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].run = { _, _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.runAgent(.presented(.runTapped))) {
			$0.runAgent?.isRunning = true
		}
		await store.receive(\.runAgent.runFinished) {
			$0.runAgent?.isRunning = false
		}
		await store.receive(\.runAgent.delegate.unauthorized) {
			$0.runAgent = nil
		}
		await store.receive(\.delegate, .unauthorized)
		// The sheet goes without a run to open.
		await store.send(.runSheetDismissed)
	}

	@Test("Cancel closes the sheet without opening anything")
	func runCancelled() async {
		var initialState = loadedState()
		initialState.runAgent = HomerRunAgentReducer.State(baseURL: Self.baseURL, agent: nightly)
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		}

		await store.send(.runAgent(.presented(.cancelTapped)))
		await store.receive(\.runAgent.dismiss) {
			$0.runAgent = nil
		}
		await store.send(.runSheetDismissed)
	}

	@Test("New Agent checks the name, creates the agent, opens its editor and reads the list again")
	func newAgentOpensEditor() async {
		let clock = TestClock()
		let created = LockIsolated<[String]>([])
		let scout = HomerAgent(name: "scout")
		let store = TestStore(initialState: loadedState()) {
			HomerAgentsReducer()
		} withDependencies: { [factory, nightly] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].create = { baseURL, name in
				#expect(baseURL == Self.baseURL)
				created.withValue { $0.append(name) }
				return name
			}
			$0[HomerAgentsClient.self].agents = { _ in [factory, nightly, scout] }
			// Answers after the list, so the two arrive in a known order.
			$0[HomerAgentEditorClient.self].files = { _, _ in
				try await clock.sleep(for: .seconds(1))
				return []
			}
		}

		await store.send(.newAgentTapped) {
			$0.newAgent = HomerNewAgentReducer.State(baseURL: Self.baseURL)
		}
		await store.send(.newAgent(.presented(.binding(.set(\.name, "my agent"))))) {
			$0.newAgent?.name = "my agent"
		}
		await store.send(.newAgent(.presented(.createTapped))) {
			$0.newAgent?.nameError = "Use letters, digits, dashes, or underscores only"
		}
		await store.send(.newAgent(.presented(.binding(.set(\.name, "scout"))))) {
			$0.newAgent?.name = "scout"
			$0.newAgent?.nameError = nil
		}
		await store.send(.newAgent(.presented(.createTapped))) {
			$0.newAgent?.isCreating = true
		}
		await store.receive(\.newAgent.createFinished) {
			$0.newAgent?.isCreating = false
		}
		await store.receive(\.newAgent.delegate.created) {
			$0.newAgent = nil
		}
		await store.receive(\.editTapped) {
			$0.editor = HomerAgentEditorReducer.State(baseURL: Self.baseURL, agentName: "scout", openedFrom: .agents)
		}
		await store.receive(\.editor.start) {
			$0.editor?.isLoadingFiles = true
		}
		await store.receive(\.agentsLoaded) {
			$0.agents = [factory, nightly, scout]
			$0.editor?.update(agent: scout)
		}
		await clock.advance(by: .seconds(1))
		await store.receive(\.editor.filesLoaded) {
			$0.editor?.isLoadingFiles = false
			$0.editor?.files = []
		}

		#expect(created.value == ["scout"])
		await store.skipInFlightEffects()
	}

	@Test("a name already taken stays in the sheet and says so; the server's other refusals in its words")
	func newAgentRefused() async {
		let store = TestStore(initialState: loadedState()) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].create = { _, name in
				if name == "factory" {
					throw HomerAPIError.server(status: 409, message: "Agent 'factory' already exists")
				}
				throw HomerAPIError.server(status: 400, message: "Invalid agent name")
			}
		}

		var sheet = HomerNewAgentReducer.State(baseURL: Self.baseURL)
		sheet.name = "factory"
		await store.send(.newAgentTapped) {
			$0.newAgent = HomerNewAgentReducer.State(baseURL: Self.baseURL)
		}
		await store.send(.newAgent(.presented(.binding(.set(\.name, "factory"))))) {
			$0.newAgent = sheet
		}
		await store.send(.newAgent(.presented(.createTapped))) {
			$0.newAgent?.isCreating = true
		}
		await store.receive(\.newAgent.createFinished) {
			$0.newAgent?.isCreating = false
			$0.newAgent?.createError = "An agent named \"factory\" already exists"
		}
		await store.send(.newAgent(.presented(.binding(.set(\.name, "con"))))) {
			$0.newAgent?.name = "con"
		}
		await store.send(.newAgent(.presented(.createTapped))) {
			$0.newAgent?.isCreating = true
			$0.newAgent?.createError = nil
		}
		await store.receive(\.newAgent.createFinished) {
			$0.newAgent?.isCreating = false
			$0.newAgent?.createError = "Invalid agent name"
		}
		await store.send(.newAgent(.presented(.cancelTapped)))
		await store.receive(\.newAgent.dismiss) {
			$0.newAgent = nil
		}
	}

	@Test("a creation answering 401 closes the sheet and asks the instance to sign out")
	func newAgentUnauthorized() async {
		var initialState = loadedState()
		var sheet = HomerNewAgentReducer.State(baseURL: Self.baseURL)
		sheet.name = "scout"
		initialState.newAgent = sheet
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].create = { _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.newAgent(.presented(.createTapped))) {
			$0.newAgent?.isCreating = true
		}
		await store.receive(\.newAgent.createFinished) {
			$0.newAgent?.isCreating = false
		}
		await store.receive(\.newAgent.delegate.unauthorized) {
			$0.newAgent = nil
		}
		await store.receive(\.delegate, .unauthorized)
	}

	@Test("a schedule's Run asks first, fires the cron and refetches the list for its last run")
	func cronRunFires() async {
		let clock = TestClock()
		let fired = LockIsolated<[String]>([])
		let ran = HomerAgent(
			name: "Nightly",
			cron: HomerAgent.Cron(
				expression: "0 3 * * *",
				timezone: "UTC",
				nextRunAt: 1_760_000_000,
				lastRunAt: 1_759_000_000,
				lastRunProcessId: 42
			)
		)
		let store = TestStore(initialState: loadedState()) {
			HomerAgentsReducer()
		} withDependencies: { [factory] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].fireCron = { baseURL, name in
				#expect(baseURL == Self.baseURL)
				fired.withValue { $0.append(name) }
			}
			$0[HomerAgentsClient.self].agents = { _ in [factory, ran] }
		}

		await store.send(.cronRunTapped(agentName: "Nightly")) {
			$0.alert = AlertState {
				TextState("Run Nightly now?")
			} actions: {
				ButtonState(action: .cronRunConfirmed(agentName: "Nightly")) {
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
		}
		await store.send(.alert(.presented(.cronRunConfirmed(agentName: "Nightly")))) {
			$0.alert = nil
			$0.cronRunsInFlight = ["Nightly"]
		}
		await store.receive(\.cronRunFinished) {
			$0.cronRunsInFlight = []
		}
		await store.receive(\.agentsLoaded) {
			$0.agents = [factory, ran]
		}
		#expect(fired.value == ["Nightly"])

		await store.send(.hidden) {
			$0.shownPage = nil
		}
	}

	@Test("a schedule's Run already on its way is not asked again")
	func cronRunInFlight() async {
		var initialState = loadedState()
		initialState.cronRunsInFlight = ["Nightly"]
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		}

		await store.send(.cronRunTapped(agentName: "Nightly"))
	}

	@Test("a refused Run says why; the 404 a non-admin gets reads as either cause")
	func cronRunRefused() async {
		var initialState = loadedState()
		initialState.cronRunsInFlight = ["Nightly"]
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		}

		await store.send(.cronRunFinished(agentName: "Nightly", .failure(HomerAPIError.server(status: 404, message: "Not found")))) {
			$0.cronRunsInFlight = []
			$0.alert = AlertState {
				TextState("Could not run Nightly")
			} actions: {
				ButtonState(role: .cancel) {
					TextState("OK")
				}
			} message: {
				TextState("Nightly is no longer loaded, or your account may not run schedules.")
			}
		}
	}

	@Test("a Run answering 401 asks the instance to sign out; one for a replaced page is dropped")
	func cronRunUnauthorized() async {
		var initialState = loadedState()
		initialState.cronRunsInFlight = ["Nightly"]
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		}

		await store.send(.cronRunFinished(agentName: "Nightly", .failure(HomerAPIError.unauthorized))) {
			$0.cronRunsInFlight = []
		}
		await store.receive(\.delegate, .unauthorized)
		await store.send(.cronRunFinished(agentName: "Nightly", .failure(HomerAPIError.unauthorized)))
	}
}
