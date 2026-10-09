import ComposableArchitecture
import Foundation
import HomerCore

/// The editor's Debug panel (the console's `debug-command-panel.tsx` and `debug-log-panel.tsx`):
/// a row per command with Debug (the run sheet) and Recall (the same command again with the
/// last rows sent), and the latest debug run's stdout and stderr, live.
///
/// The console streams each log from byte 0 and drops what a reconnect sends again; here the
/// tail resumes from the last byte received (`Last-Event-ID`), as the process page's does.
@Reducer
public struct HomerAgentDebugReducer: Sendable {
	/// How long the tail waits before reconnecting, doubling up to `maxReconnectDelay`.
	static let reconnectDelay: Duration = .seconds(1)
	static let maxReconnectDelay: Duration = .seconds(30)
	/// Failures in a row before the tail gives up. A 404 is not one: a command's log exists only
	/// once the command has started.
	static let maxReconnectAttempts = 6

	/// The rows a command's last debug run was started with.
	public struct LastParams: Equatable, Sendable {
		public var env: [HomerKeyValue]
		public var params: [HomerKeyValue]
	}

	/// One stream of the run's command output.
	public struct Output: Equatable, Sendable {
		public var text = ""
		/// Bytes of the log `text` holds — where the tail resumes.
		var byteCount = 0
		/// The server sent `log.end`: the run is over and everything was sent.
		public var hasEnded = false
		public var isTailing = false
		public var error: String?
	}

	/// The debug run the log panel shows.
	public struct ActiveRun: Equatable, Sendable {
		public let processId: Int
		public let commandIndex: Int
		public var outputs: [HomerOutputStream: Output] = [.stdout: Output(), .stderr: Output()]

		public init(processId: Int, commandIndex: Int) {
			self.processId = processId
			self.commandIndex = commandIndex
		}

		public func output(_ stream: HomerOutputStream) -> Output {
			outputs[stream] ?? Output()
		}
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let agentName: String
		/// The agent's command count (`scriptCount`), one row each.
		public internal(set) var commandCount: Int
		public internal(set) var inputs: [HomerAgent.Input]
		/// By command index, for this editor's lifetime, as the console keeps them per page.
		public internal(set) var lastParams: [Int: LastParams] = [:]
		/// The command whose Recall is waiting on the server.
		public internal(set) var recallInFlight: Int?
		public internal(set) var recallError: String?
		public internal(set) var activeRun: ActiveRun?
		@Presents
		public var runSheet: HomerAgentDebugRunReducer.State?

		public init(baseURL: String, agentName: String, agent: HomerAgent?) {
			self.baseURL = baseURL
			self.agentName = agentName
			commandCount = agent?.scriptCount ?? 0
			inputs = agent?.inputs ?? []
		}

		/// The agents list's poll brought a newer definition (a save reloads it on the server).
		mutating func update(from agent: HomerAgent) {
			commandCount = agent.scriptCount
			inputs = agent.inputs
		}

		/// The tails were cancelled from outside (the page went off screen); `resumeTails`
		/// picks them up again where they stopped.
		mutating func pauseTails() {
			for stream in HomerOutputStream.allCases {
				activeRun?.outputs[stream]?.isTailing = false
			}
		}
	}

	public enum Action {
		/// Opens the run sheet for the command, with its last rows or the declared inputs.
		case runTapped(commandIndex: Int)
		case recallTapped(commandIndex: Int)
		case recallFinished(commandIndex: Int, Result<Int, any Error>)
		case runSheet(PresentationAction<HomerAgentDebugRunReducer.Action>)
		case closeRunTapped
		case processTapped
		case logEvent(processId: Int, HomerOutputStream, HomerLogEvent)
		case tailStopped(processId: Int, HomerOutputStream, failure: String?)
		/// Follows again whatever stream of the run has not ended.
		case resumeTails
		case delegate(Delegate)

		public enum Delegate: Equatable, Sendable {
			case openProcess(processId: Int)
			case unauthorized
		}
	}

	nonisolated enum CancelID: Hashable {
		case recall
		case tail(HomerOutputStream)
	}

	/// Stops the log tails, which run until the run ends.
	static func cancelTails<A>() -> Effect<A> {
		.merge(HomerOutputStream.allCases.map { .cancel(id: CancelID.tail($0)) })
	}

	/// Stops whatever the panel still runs (see `HomerAgentEditorReducer.cancelEffects`).
	static func cancelEffects<A>() -> Effect<A> {
		.merge(
			cancelTails(),
			.cancel(id: CancelID.recall),
			.cancel(id: HomerAgentDebugRunReducer.CancelID.run)
		)
	}

	@Dependency(HomerAgentEditorClient.self)
	private var editorClient

	@Dependency(\.continuousClock)
	private var clock

	@Dependency(\.uuid)
	private var uuid

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .runTapped(commandIndex):
				let last = state.lastParams[commandIndex]
				state.runSheet = HomerAgentDebugRunReducer.State(
					baseURL: state.baseURL,
					agentName: state.agentName,
					commandIndex: commandIndex,
					inputs: state.inputs,
					params: last?.params ?? state.inputs.map { HomerKeyValue(id: uuid(), key: $0.paramName) },
					env: last?.env ?? []
				)
				return .none

			case let .recallTapped(commandIndex):
				guard let last = state.lastParams[commandIndex], state.recallInFlight == nil else {
					return .none
				}
				state.recallInFlight = commandIndex
				state.recallError = nil
				let request = HomerAgentDebugRequest(commandIndex: commandIndex, env: last.env, params: last.params)
				return .run { [baseURL = state.baseURL, agentName = state.agentName] send in
					await send(.recallFinished(
						commandIndex: commandIndex,
						Result { try await editorClient.debug(baseURL, agentName, request) }
					))
				}
				.cancellable(id: CancelID.recall, cancelInFlight: true)

			case let .recallFinished(commandIndex, .success(processId)):
				state.recallInFlight = nil
				return start(&state, processId: processId, commandIndex: commandIndex)

			case let .recallFinished(_, .failure(error)):
				state.recallInFlight = nil
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.recallError = error.localizedDescription
				return .none

			case let .runSheet(.presented(.delegate(.started(processId, env, params)))):
				guard let commandIndex = state.runSheet?.commandIndex else {
					return .none
				}
				state.lastParams[commandIndex] = LastParams(env: env, params: params)
				state.runSheet = nil
				return start(&state, processId: processId, commandIndex: commandIndex)

			case .runSheet(.presented(.delegate(.unauthorized))):
				state.runSheet = nil
				return .send(.delegate(.unauthorized))

			case .runSheet:
				return .none

			case .closeRunTapped:
				state.activeRun = nil
				return Self.cancelTails()

			case .processTapped:
				guard let processId = state.activeRun?.processId else {
					return .none
				}
				return .send(.delegate(.openProcess(processId: processId)))

			case let .logEvent(processId, stream, .chunk(text, endOffset)):
				guard state.activeRun?.processId == processId,
				      let byteCount = state.activeRun?.outputs[stream]?.byteCount,
				      endOffset > byteCount
				else {
					return .none
				}
				// In place: a copy of the output would copy the whole log for every chunk.
				state.activeRun?.outputs[stream]?.text += text
				state.activeRun?.outputs[stream]?.byteCount = endOffset
				return .none

			case let .logEvent(processId, stream, .end):
				guard state.activeRun?.processId == processId else {
					return .none
				}
				state.activeRun?.outputs[stream]?.hasEnded = true
				state.activeRun?.outputs[stream]?.isTailing = false
				return .none

			case let .tailStopped(processId, stream, failure):
				guard state.activeRun?.processId == processId else {
					return .none
				}
				state.activeRun?.outputs[stream]?.isTailing = false
				state.activeRun?.outputs[stream]?.error = failure
				return .none

			case .resumeTails:
				guard let run = state.activeRun else {
					return .none
				}
				let streams = HomerOutputStream.allCases.filter {
					!run.output($0).hasEnded && !run.output($0).isTailing
				}
				return .merge(streams.map { tail(&state, stream: $0) })

			case .delegate:
				return .none
			}
		}
		.ifLet(\.$runSheet, action: \.runSheet) {
			HomerAgentDebugRunReducer()
		}
	}

	/// Shows the new run in the log panel, in place of the last one, and follows its output.
	private func start(_ state: inout State, processId: Int, commandIndex: Int) -> Effect<Action> {
		state.activeRun = ActiveRun(processId: processId, commandIndex: commandIndex)
		return .merge(HomerOutputStream.allCases.map { tail(&state, stream: $0) })
	}

	/// Follows the stream from the last byte received until the server says the run is over,
	/// reconnecting when the connection drops — and, until the command starts writing, while
	/// the log is not there yet.
	private func tail(_ state: inout State, stream: HomerOutputStream) -> Effect<Action> {
		guard let run = state.activeRun else {
			return .none
		}
		state.activeRun?.outputs[stream]?.isTailing = true
		state.activeRun?.outputs[stream]?.error = nil
		return .run { [baseURL = state.baseURL, start = run.output(stream).byteCount] send in
			var offset = start
			var failures = 0
			var waits = 0
			while true {
				do {
					for try await event in editorClient.logEvents(baseURL, run.processId, run.commandIndex, stream, offset) {
						if case let .chunk(_, endOffset) = event {
							offset = endOffset
							failures = 0
						}
						await send(.logEvent(processId: run.processId, stream, event))
						if event == .end {
							return
						}
					}
				}
				catch HomerAPIError.unauthorized {
					await send(.delegate(.unauthorized))
					return
				}
				catch HomerAPIError.server(status: 404, _) {
					waits += 1
					try await clock.sleep(for: min(Self.reconnectDelay * (1 << min(waits, 5)), Self.maxReconnectDelay))
					continue
				}
				catch {
					failures += 1
					if failures > Self.maxReconnectAttempts {
						await send(.tailStopped(
							processId: run.processId,
							stream,
							failure: "Live output stopped: \(error.localizedDescription)"
						))
						return
					}
				}
				let delay = Self.reconnectDelay * (1 << min(failures, 5))
				try await clock.sleep(for: min(delay, Self.maxReconnectDelay))
			}
		}
		.cancellable(id: CancelID.tail(stream), cancelInFlight: true)
	}
}
