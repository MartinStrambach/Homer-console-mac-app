import ComposableArchitecture
import Foundation
import HomerCore

/// One command's output (`view-artifact-dialog.tsx`): its stdout and stderr, an LLM harness
/// command's stdout as the conversation, and live while the command still writes it.
///
/// The file is read once over REST, and while the server says it is not complete, tailed from
/// the byte the read ended at — the log stream resumes from any offset (`Last-Event-ID`), so
/// nothing is fetched twice. The console instead streams from byte 0 and swaps buffers.
///
/// The conversation is the server's translation of the stdout (`/llm-events`), followed from the
/// start and, after a dropped connection, from the last event received. The conversation and
/// the raw file are each read only once shown.
@Reducer
public struct HomerProcessOutputReducer: Sendable {
	/// How long the tail waits before reconnecting, doubling up to `maxReconnectDelay`.
	static let reconnectDelay: Duration = .seconds(1)
	static let maxReconnectDelay: Duration = .seconds(30)
	static let maxReconnectAttempts = 6

	public enum Mode: Equatable, Sendable {
		/// The harness's messages and tool calls.
		case conversation
		case raw
	}

	public struct Output: Equatable, Sendable {
		public var text = ""
		/// Bytes of the file `text` holds — where the tail resumes.
		var byteCount = 0
		public var isComplete = true
		public var isLoading = false
		public var isTailing = false
		public var error: String?
		public var hasLoaded = false

		public init() {}
	}

	/// The stdout's conversation, as the server translates it.
	public struct Conversation: Equatable, Sendable {
		public var conversation = HomerLLMConversation()
		/// The last event applied — where a reconnect resumes, and what tells a replay or a new
		/// attempt apart.
		var cursor: HomerLLMCursor?
		public var hasStarted = false
		public var isStreaming = false
		/// Some event arrived (in this attempt).
		public var hasEvents = false
		/// The command is done and the stream drained.
		public var hasEnded = false
		public var error: String?
		/// The server has no conversation for the command (404): a server before Homer 1.27, or
		/// a command it cannot translate. The sheet falls back to the raw output.
		public var isUnavailable = false

		public init() {}
	}

	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let processId: Int
		public let executionIndex: Int
		/// The files of each stream; a stream without one has no output to show.
		public let paths: [HomerOutputStream: String]
		public var stream: HomerOutputStream
		/// The harness the command runs; nil for any other command.
		public let harness: HomerLLMHarness?
		/// Picked by the user; nil follows the command: the conversation for a harness's stdout.
		public var mode: Mode?
		public internal(set) var outputs: [HomerOutputStream: Output] = [:]
		public internal(set) var conversation = Conversation()
		/// The command is still running — its files may not exist yet.
		public let isLiveCommand: Bool
		/// When the running command started, for the live header's clock.
		public let commandStart: Double?
		/// How a finished harness command was priced, for the conversation's summary; nil while
		/// it runs and for any other command.
		public let llmAccounting: HomerLLMAccounting?

		public init(
			baseURL: String,
			processId: Int,
			executionIndex: Int,
			paths: [HomerOutputStream: String],
			stream: HomerOutputStream,
			harness: HomerLLMHarness? = nil,
			isLiveCommand: Bool = false,
			commandStart: Double? = nil,
			llmAccounting: HomerLLMAccounting? = nil
		) {
			self.baseURL = baseURL
			self.processId = processId
			self.executionIndex = executionIndex
			self.paths = paths
			self.stream = stream
			self.harness = harness
			self.isLiveCommand = isLiveCommand
			self.commandStart = commandStart
			self.llmAccounting = llmAccounting
		}

		public var output: Output {
			outputs[stream] ?? Output()
		}

		public var path: String? {
			paths[stream]
		}

		/// The stdout of a harness's command can be read as its conversation, unless the server
		/// has none for it.
		public var offersConversation: Bool {
			harness != nil && stream == .stdout && !conversation.isUnavailable
		}

		public var effectiveMode: Mode {
			offersConversation ? mode ?? .conversation : .raw
		}

		public var showsConversation: Bool {
			effectiveMode == .conversation
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case task
		case refreshTapped
		case loaded(HomerOutputStream, Result<HomerArtifactContent, any Error>)
		case logEvent(HomerOutputStream, HomerLogEvent)
		case tailStopped(HomerOutputStream, failure: String?)
		case llmEvent(HomerLLMStreamEvent)
		/// The conversation stream gave up: `unavailable` when the server has none for the
		/// command.
		case conversationStopped(failure: String?, unavailable: Bool)
		case delegate(Delegate)

		public enum Delegate: Equatable, Sendable {
			case unauthorized
		}
	}

	private nonisolated enum CancelID: Hashable {
		case load
		case tail
		case conversation
	}

	@Dependency(HomerProcessDetailClient.self)
	private var client

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.stream):
				// Each stream decides its own mode, as the console resets it on a tab switch.
				state.mode = nil
				return state.showsConversation ? followConversation(&state) : load(&state)

			case .binding(\.mode):
				if state.showsConversation {
					return followConversation(&state)
				}
				let output = state.output
				return output.hasLoaded || output.isLoading ? .none : load(&state)

			case .binding:
				return .none

			case .task:
				return state.showsConversation ? followConversation(&state) : load(&state)

			case .refreshTapped:
				guard state.showsConversation else {
					return load(&state)
				}
				state.conversation = Conversation()
				return followConversation(&state)

			case let .loaded(stream, .success(content)):
				var output = Output()
				output.text = content.text
				output.byteCount = content.byteCount
				output.isComplete = content.isComplete
				output.hasLoaded = true
				state.outputs[stream] = output
				return output.isComplete ? .none : tail(&state, stream: stream)

			case let .loaded(stream, .failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				// A running command's file appears with its first byte: until then the tail
				// waits for it.
				if state.isLiveCommand, case .server(status: 404, _) = error as? HomerAPIError {
					var output = Output()
					output.isComplete = false
					output.hasLoaded = true
					state.outputs[stream] = output
					return tail(&state, stream: stream)
				}
				state.outputs[stream, default: Output()].isLoading = false
				state.outputs[stream, default: Output()].error = error.localizedDescription
				return .none

			case let .logEvent(stream, .chunk(text, endOffset)):
				guard let byteCount = state.outputs[stream]?.byteCount, endOffset > byteCount else {
					return .none
				}
				// In place: a copy of the output would copy the whole log for every chunk.
				state.outputs[stream]?.text += text
				state.outputs[stream]?.byteCount = endOffset
				return .none

			case let .logEvent(stream, .end):
				state.outputs[stream]?.isComplete = true
				state.outputs[stream]?.isTailing = false
				return .none

			case let .tailStopped(stream, failure):
				state.outputs[stream]?.isTailing = false
				if let failure {
					state.outputs[stream]?.error = failure
				}
				return .none

			case let .llmEvent(.event(event, cursor)):
				switch cursor?.placement(after: state.conversation.cursor) ?? .next {
				case .replay:
					return .none
				case .newAttempt:
					// A retry writes its own output from the start: its conversation replaces the
					// failed attempt's.
					state.conversation.conversation = HomerLLMConversation()
				case .next:
					break
				}
				state.conversation.cursor = cursor ?? state.conversation.cursor
				state.conversation.hasEvents = true
				state.conversation.conversation.apply(event)
				return .none

			case .llmEvent(.end):
				state.conversation.hasEnded = true
				state.conversation.isStreaming = false
				return .none

			case let .conversationStopped(failure, unavailable):
				state.conversation.isStreaming = false
				guard unavailable else {
					state.conversation.error = failure
					return .none
				}
				state.conversation.isUnavailable = true
				state.mode = nil
				return state.output.hasLoaded ? .none : load(&state)

			case .delegate:
				return .none
			}
		}
	}

	/// Follows the conversation from the last event received — from the start the first time —
	/// until the command is done, reconnecting when the connection drops.
	private func followConversation(_ state: inout State) -> Effect<Action> {
		guard !state.conversation.isStreaming, !state.conversation.hasEnded else {
			return .none
		}
		state.conversation.hasStarted = true
		state.conversation.isStreaming = true
		state.conversation.error = nil
		return .run { [baseURL = state.baseURL, processId = state.processId, index = state.executionIndex, start = state.conversation.cursor?.id] send in
			var lastEventID = start
			var failures = 0
			while true {
				do {
					for try await event in client.llmEvents(baseURL, processId, index, lastEventID) {
						if case let .event(_, cursor?) = event {
							lastEventID = cursor.id
							failures = 0
						}
						await send(.llmEvent(event))
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
					await send(.conversationStopped(failure: nil, unavailable: true))
					return
				}
				catch {
					failures += 1
					if failures > Self.maxReconnectAttempts {
						await send(.conversationStopped(
							failure: "Live conversation stopped: \(error.localizedDescription)",
							unavailable: false
						))
						return
					}
				}
				let delay = Self.reconnectDelay * (1 << min(failures, 5))
				try await clock.sleep(for: min(delay, Self.maxReconnectDelay))
			}
		}
		.cancellable(id: CancelID.conversation, cancelInFlight: true)
	}

	private func load(_ state: inout State) -> Effect<Action> {
		let stream = state.stream
		guard let path = state.path else {
			return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.tail))
		}
		state.outputs[stream, default: Output()].isLoading = true
		state.outputs[stream, default: Output()].error = nil
		return .merge(
			.cancel(id: CancelID.tail),
			.run { [baseURL = state.baseURL, processId = state.processId] send in
				await send(.loaded(stream, Result {
					try await client.artifactContent(baseURL, processId, path)
				}))
			}
			.cancellable(id: CancelID.load, cancelInFlight: true)
		)
	}

	/// Follows the file from where the read ended until the server says the run is over,
	/// reconnecting from the last byte received when the connection drops.
	private func tail(_ state: inout State, stream: HomerOutputStream) -> Effect<Action> {
		guard let output = state.outputs[stream] else {
			return .none
		}
		state.outputs[stream]?.isTailing = true
		return .run { [baseURL = state.baseURL, processId = state.processId, index = state.executionIndex, start = output.byteCount] send in
			var offset = start
			var failures = 0
			while true {
				do {
					for try await event in client.logEvents(baseURL, processId, index, stream, offset) {
						if case let .chunk(_, endOffset) = event {
							offset = endOffset
							failures = 0
						}
						await send(.logEvent(stream, event))
						if event == .end {
							return
						}
					}
				}
				catch HomerAPIError.unauthorized {
					await send(.delegate(.unauthorized))
					return
				}
				catch {
					failures += 1
					if failures > Self.maxReconnectAttempts {
						await send(.tailStopped(stream, failure: "Live output stopped: \(error.localizedDescription)"))
						return
					}
				}
				let delay = Self.reconnectDelay * (1 << min(failures, 5))
				try await clock.sleep(for: min(delay, Self.maxReconnectDelay))
			}
		}
		.cancellable(id: CancelID.tail, cancelInFlight: true)
	}
}
