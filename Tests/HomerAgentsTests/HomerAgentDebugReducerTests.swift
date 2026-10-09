import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerAgents
@testable import HomerCore
import Testing

@MainActor
@Suite("Homer agent debug runs", .dependencies)
struct HomerAgentDebugReducerTests {
	private nonisolated static let baseURL = "https://homer.example.com"
	private let factory = HomerAgent(
		name: "factory",
		inputs: [HomerAgent.Input(paramName: "ticket", envName: "TICKET")],
		scriptCount: 2
	)

	private func state() -> HomerAgentDebugReducer.State {
		HomerAgentDebugReducer.State(baseURL: Self.baseURL, agentName: "factory", agent: factory)
	}

	/// stdout says hello and ends; stderr is not written yet, and waited for.
	private nonisolated static func finishedLogs(
		_ baseURL: String,
		_ processId: Int,
		_ commandIndex: Int,
		_ stream: HomerOutputStream,
		_ offset: Int
	) -> AsyncThrowingStream<HomerLogEvent, any Error> {
		AsyncThrowingStream { continuation in
			guard stream == .stdout else {
				continuation.finish(throwing: HomerAPIError.server(status: 404, message: nil))
				return
			}
			continuation.yield(.chunk(text: "hello\n", endOffset: 6))
			continuation.yield(.end)
			continuation.finish()
		}
	}

	@Test("a debug run starts from the sheet, keeps its rows for Recall and shows its output")
	func runAndRecall() async {
		let requests = LockIsolated<[HomerAgentDebugRequest]>([])
		let params = [HomerKeyValue(id: UUID(0), key: "ticket", value: "AIF-1")]
		let env = [HomerKeyValue(id: UUID(1), key: "DEBUG", value: "1")]
		let store = TestStore(initialState: state()) {
			HomerAgentDebugReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0.uuid = .incrementing
			$0[HomerAgentEditorClient.self].debug = { baseURL, agentName, request in
				#expect(baseURL == Self.baseURL)
				#expect(agentName == "factory")
				requests.withValue { $0.append(request) }
				return 41 + requests.value.count
			}
			$0[HomerAgentEditorClient.self].logEvents = Self.finishedLogs
		}

		// The declared inputs, empty, to start with.
		await store.send(.runTapped(commandIndex: 1)) {
			$0.runSheet = HomerAgentDebugRunReducer.State(
				baseURL: Self.baseURL,
				agentName: "factory",
				commandIndex: 1,
				inputs: factory.inputs,
				params: [HomerKeyValue(id: UUID(0), key: "ticket")],
				env: []
			)
		}
		#expect(store.state.runSheet?.declaredInput(named: " ticket ")?.envName == "TICKET")
		await store.send(.runSheet(.presented(.binding(.set(\.params, IdentifiedArray(uniqueElements: params)))))) {
			$0.runSheet?.params = IdentifiedArray(uniqueElements: params)
		}
		await store.send(.runSheet(.presented(.addEnvTapped))) {
			$0.runSheet?.env = [HomerKeyValue(id: UUID(1))]
		}
		await store.send(.runSheet(.presented(.binding(.set(\.env, IdentifiedArray(uniqueElements: env)))))) {
			$0.runSheet?.env = IdentifiedArray(uniqueElements: env)
		}
		await store.send(.runSheet(.presented(.runTapped))) {
			$0.runSheet?.isRunning = true
		}
		await store.receive(\.runSheet.runFinished) {
			$0.runSheet?.isRunning = false
		}
		await store.receive(\.runSheet.delegate.started) {
			$0.lastParams[1] = HomerAgentDebugReducer.LastParams(env: env, params: params)
			$0.runSheet = nil
			var run = HomerAgentDebugReducer.ActiveRun(processId: 42, commandIndex: 1)
			run.outputs[.stdout]?.isTailing = true
			run.outputs[.stderr]?.isTailing = true
			$0.activeRun = run
		}
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.text = "hello\n"
			$0.activeRun?.outputs[.stdout]?.byteCount = 6
		}
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.hasEnded = true
			$0.activeRun?.outputs[.stdout]?.isTailing = false
		}
		#expect(requests.value == [HomerAgentDebugRequest(commandIndex: 1, env: ["DEBUG": "1"], queryParams: ["ticket": "AIF-1"])])

		// Recall runs the command again with the same rows; the sheet opens with them too.
		await store.send(.recallTapped(commandIndex: 1)) {
			$0.recallInFlight = 1
		}
		await store.receive(\.recallFinished) {
			$0.recallInFlight = nil
			var run = HomerAgentDebugReducer.ActiveRun(processId: 43, commandIndex: 1)
			run.outputs[.stdout]?.isTailing = true
			run.outputs[.stderr]?.isTailing = true
			$0.activeRun = run
		}
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.text = "hello\n"
			$0.activeRun?.outputs[.stdout]?.byteCount = 6
		}
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.hasEnded = true
			$0.activeRun?.outputs[.stdout]?.isTailing = false
		}
		#expect(requests.value.count == 2 && requests.value[1] == requests.value[0])

		// A command never run has nothing to recall.
		await store.send(.recallTapped(commandIndex: 0))

		await store.send(.processTapped)
		await store.receive(\.delegate, .openProcess(processId: 43))
		await store.send(.closeRunTapped) {
			$0.activeRun = nil
		}
	}

	@Test("the log is waited for until the command writes it, then followed from where it stopped")
	func waitsForLog() async {
		let clock = TestClock()
		let calls = LockIsolated<[Int]>([])
		var initialState = state()
		initialState.activeRun = HomerAgentDebugReducer.ActiveRun(processId: 42, commandIndex: 0)
		initialState.activeRun?.outputs[.stderr]?.hasEnded = true
		let store = TestStore(initialState: initialState) {
			HomerAgentDebugReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerAgentEditorClient.self].logEvents = { _, _, _, stream, offset in
				#expect(stream == .stdout)
				calls.withValue { $0.append(offset) }
				let call = calls.value.count
				return AsyncThrowingStream { continuation in
					switch call {
					case 1:
						continuation.finish(throwing: HomerAPIError.server(status: 404, message: nil))
					case 2:
						continuation.yield(.chunk(text: "abc", endOffset: 3))
						continuation.finish(throwing: HomerAPIError.unreachable("reset"))
					default:
						continuation.yield(.chunk(text: "def", endOffset: 6))
						continuation.yield(.end)
						continuation.finish()
					}
				}
			}
		}

		await store.send(.resumeTails) {
			$0.activeRun?.outputs[.stdout]?.isTailing = true
		}
		await clock.advance(by: HomerAgentDebugReducer.reconnectDelay * 2)
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.text = "abc"
			$0.activeRun?.outputs[.stdout]?.byteCount = 3
		}
		await clock.advance(by: HomerAgentDebugReducer.reconnectDelay * 2)
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.text = "abcdef"
			$0.activeRun?.outputs[.stdout]?.byteCount = 6
		}
		await store.receive(\.logEvent) {
			$0.activeRun?.outputs[.stdout]?.hasEnded = true
			$0.activeRun?.outputs[.stdout]?.isTailing = false
		}
		#expect(calls.value == [0, 0, 3])
	}

	@Test("a refused debug run says why in the sheet")
	func refused() async {
		var initialState = state()
		initialState.runSheet = HomerAgentDebugRunReducer.State(
			baseURL: Self.baseURL,
			agentName: "factory",
			commandIndex: 0,
			inputs: [],
			params: [],
			env: []
		)
		let store = TestStore(initialState: initialState) {
			HomerAgentDebugReducer()
		} withDependencies: {
			$0[HomerAgentEditorClient.self].debug = { _, _, _ in
				throw HomerAPIError.server(status: 409, message: "Agent is locked by run #7")
			}
		}

		await store.send(.runSheet(.presented(.runTapped))) {
			$0.runSheet?.isRunning = true
		}
		await store.receive(\.runSheet.runFinished) {
			$0.runSheet?.isRunning = false
			$0.runSheet?.runError = "Agent is locked by run #7"
		}
	}
}
