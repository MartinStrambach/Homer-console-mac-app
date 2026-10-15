import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerAgents
@testable import HomerCore
import Testing

@MainActor
@Suite("Homer command bar", .dependencies)
struct HomerCommandBarReducerTests {
	private nonisolated static let baseURL = "https://homer.example.com"
	private let factory = HomerCommand(command: "", agent: "factory", promptParam: "ticket_id")
	private let check = HomerCommand(command: "check", agent: "factory-check", promptParam: "ticket_id")
	private let contract = HomerCommand(command: "contract", agent: "factory-qa-contract-now", promptParam: "ticket_id")

	private func loadedState(text: String = "") -> HomerCommandBarReducer.State {
		var state = HomerCommandBarReducer.State(baseURL: Self.baseURL)
		state.commands = .loaded(HomerCommandList(intro: "Hi", commands: [factory, check, contract]))
		state.text = text
		return state
	}

	@Test("opening reads the commands")
	func loads() async {
		let list = HomerCommandList(commands: [factory, check])
		let store = TestStore(initialState: HomerCommandBarReducer.State(baseURL: Self.baseURL)) {
			HomerCommandBarReducer()
		} withDependencies: {
			$0[HomerCommandsClient.self].commands = { _ in list }
		}

		await store.send(.appeared)
		await store.receive(\.commandsLoaded) {
			$0.commands = .loaded(list)
		}
	}

	@Test("a server without the endpoint says so")
	func unsupported() async {
		let store = TestStore(initialState: HomerCommandBarReducer.State(baseURL: Self.baseURL)) {
			HomerCommandBarReducer()
		} withDependencies: {
			$0[HomerCommandsClient.self].commands = { _ in nil }
		}

		await store.send(.appeared)
		await store.receive(\.commandsLoaded) {
			$0.commands = .unsupported
		}
	}

	@Test("a command runs its agent with the rest as the prompt, and the run opens")
	func runsAndOpens() async {
		let sent = LockIsolated<(String, HomerAgentRunRequest)?>(nil)
		let store = TestStore(initialState: loadedState(text: "check MOB-1234")) {
			HomerCommandBarReducer()
		} withDependencies: {
			$0[HomerCommandsClient.self].run = { _, agent, request in
				sent.setValue((agent, request))
				return 43
			}
		}

		await store.send(.runTapped) {
			$0.isRunning = true
		}
		await store.receive(\.runFinished) {
			$0.isRunning = false
		}
		await store.receive(\.delegate, .openProcess(processId: 43))

		#expect(sent.value?.0 == "factory-check")
		#expect(sent.value?.1 == HomerAgentRunRequest(queryItems: [URLQueryItem(name: "ticket_id", value: "MOB-1234")]))
	}

	@Test("text naming no command runs the default command with all of it")
	func runsDefault() async {
		let sent = LockIsolated<(String, HomerAgentRunRequest)?>(nil)
		let store = TestStore(initialState: loadedState(text: "change MOB-1234 rename it")) {
			HomerCommandBarReducer()
		} withDependencies: {
			$0[HomerCommandsClient.self].run = { _, agent, request in
				sent.setValue((agent, request))
				return 44
			}
		}

		await store.send(.runTapped) {
			$0.isRunning = true
		}
		await store.receive(\.runFinished) {
			$0.isRunning = false
		}
		await store.receive(\.delegate, .openProcess(processId: 44))

		#expect(sent.value?.0 == "factory")
		#expect(sent.value?.1.queryItems == [URLQueryItem(name: "ticket_id", value: "change MOB-1234 rename it")])
	}

	@Test("a refused run says why; an expired session goes to the instance")
	func runFails() async {
		let store = TestStore(initialState: loadedState(text: "check MOB-1")) {
			HomerCommandBarReducer()
		} withDependencies: {
			$0[HomerCommandsClient.self].run = { _, _, _ in throw HomerAPIError.server(status: 429, message: "Cost cap reached") }
		}

		await store.send(.runTapped) {
			$0.isRunning = true
		}
		await store.receive(\.runFinished) {
			$0.isRunning = false
			$0.runError = HomerAPIError.server(status: 429, message: "Cost cap reached").localizedDescription
		}

		store.dependencies[HomerCommandsClient.self].run = { _, _, _ in throw HomerAPIError.unauthorized }
		await store.send(.runTapped) {
			$0.isRunning = true
			$0.runError = nil
		}
		await store.receive(\.runFinished) {
			$0.isRunning = false
		}
		await store.receive(\.delegate, .unauthorized)
	}

	@Test("empty text and help run nothing")
	func nothingToRun() async {
		let store = TestStore(initialState: loadedState(text: "help")) {
			HomerCommandBarReducer()
		}

		await store.send(.runTapped)
		await store.send(.binding(.set(\.text, "  "))) {
			$0.text = "  "
		}
		await store.send(.runTapped)
	}

	@Test("suggestions follow the first word, and Tab completes it")
	func suggestionsAndCompletion() async {
		let store = TestStore(initialState: loadedState(text: "c")) {
			HomerCommandBarReducer()
		}
		#expect(store.state.suggestions == [check, contract])

		await store.send(.binding(.set(\.text, "con"))) {
			$0.text = "con"
		}
		#expect(store.state.suggestions == [contract])

		await store.send(.completeTapped) {
			$0.text = "contract "
		}
		#expect(store.state.suggestions.isEmpty)

		await store.send(.binding(.set(\.text, "help"))) {
			$0.text = "help"
		}
		#expect(store.state.suggestions == [factory, check, contract])
	}
}
