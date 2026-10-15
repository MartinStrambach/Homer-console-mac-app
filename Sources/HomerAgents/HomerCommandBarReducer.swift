import ComposableArchitecture
import Foundation
import HomerCore

/// The command bar (⌘K): `<command> <text>` runs what the same words run as a mention of the
/// instance's Slack connector — the commands are the connector's, served by Homer — and the new
/// run opens.
@Reducer
public struct HomerCommandBarReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public enum Commands: Equatable, Sendable {
			case loading
			case loaded(HomerCommandList)
			/// The server predates `GET /api/v1/commands`.
			case unsupported
			case failed(String)
		}

		public let baseURL: String
		public var text = ""
		/// Read each time the bar opens: the connector's config can change under a running server.
		public internal(set) var commands: Commands = .loading
		public internal(set) var isRunning = false
		public internal(set) var runError: String?

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		var commandList: [HomerCommand] {
			if case let .loaded(list) = commands {
				return list.commands
			}
			return []
		}

		/// Where the text goes; nil until the commands are read, or while there is no text.
		public var route: HomerCommandRoute? {
			guard case .loaded = commands, !HomerCommandRoute.stripMention(text).isEmpty else {
				return nil
			}
			return HomerCommandRoute(text: text, commands: commandList)
		}

		/// The commands offered under the field: those whose word starts with what is typed
		/// while the first word is being typed, every one after `help` or before any text.
		public var suggestions: [HomerCommand] {
			guard !HomerCommandRoute.stripMention(text).isEmpty, route != .help else {
				return commandList
			}
			let typed = text.drop(while: \.isWhitespace)
			guard !typed.contains(where: \.isWhitespace) else {
				return []
			}
			return commandList.filter { !$0.isDefault && $0.command.lowercased().hasPrefix(typed.lowercased()) }
		}

		public var canRun: Bool {
			if case .command = route {
				return !isRunning
			}
			return false
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case appeared
		case commandsLoaded(Result<HomerCommandList?, any Error>)
		/// A suggestion clicked: its word goes in the field, ready for its text.
		case suggestionTapped(HomerCommand)
		/// Tab: the first suggestion's word goes in the field.
		case completeTapped
		case runTapped
		case runFinished(Result<Int, any Error>)
		case delegate(HomerPageDelegate)
	}

	private nonisolated enum CancelID: Hashable {
		case load
		case run
	}

	@Dependency(HomerCommandsClient.self)
	private var commandsClient

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.text):
				state.runError = nil
				return .none

			case .binding:
				return .none

			case .appeared:
				return .run { [baseURL = state.baseURL] send in
					await send(.commandsLoaded(Result { try await commandsClient.commands(baseURL) }))
				}
				.cancellable(id: CancelID.load, cancelInFlight: true)

			case let .commandsLoaded(.success(list)):
				state.commands = list.map { .loaded($0) } ?? .unsupported
				return .none

			case let .commandsLoaded(.failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.commands = .failed(error.localizedDescription)
				return .none

			case let .suggestionTapped(command):
				state.text = command.isDefault ? "" : command.command + " "
				state.runError = nil
				return .none

			case .completeTapped:
				guard let first = state.suggestions.first(where: { !$0.isDefault }),
				      !HomerCommandRoute.stripMention(state.text).isEmpty
				else {
					return .none
				}
				state.text = first.command + " "
				return .none

			case .runTapped:
				guard state.canRun, case let .command(command, prompt) = state.route else {
					return .none
				}
				state.isRunning = true
				state.runError = nil
				return .run { [baseURL = state.baseURL] send in
					await send(.runFinished(Result {
						try await commandsClient.run(baseURL, command.agent, command.runRequest(prompt: prompt))
					}))
				}
				.cancellable(id: CancelID.run, cancelInFlight: true)

			case let .runFinished(.success(processId)):
				state.isRunning = false
				return .send(.delegate(.openProcess(processId: processId)))

			case let .runFinished(.failure(error)):
				state.isRunning = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.runError = error.localizedDescription
				return .none

			case .delegate:
				return .none
			}
		}
	}
}
