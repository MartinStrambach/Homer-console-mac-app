import ComposableArchitecture
import Foundation
import HomerCore

/// The New Agent sheet (the console's `new-agent-dialog.tsx`): a name, checked as the console
/// checks it, from which the server makes an agent directory with a minimal `agent.yaml`. The
/// new agent opens in its editor, as the console takes you there.
@Reducer
public struct HomerNewAgentReducer: Sendable {
	@ObservableState
	public struct State: Equatable, Identifiable {
		public let baseURL: String
		public var name = ""
		/// The name's problem, found before anything is sent.
		public internal(set) var nameError: String?
		/// Why the server did not create it.
		public internal(set) var createError: String?
		public internal(set) var isCreating = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		public var id: String {
			baseURL
		}

		public var canCreate: Bool {
			!isCreating && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case createTapped
		case createFinished(name: String, Result<String, any Error>)
		case cancelTapped
		case delegate(Delegate)

		@CasePathable
		public enum Delegate: Equatable, Sendable {
			/// The agent exists; the sheet's owner closes it and opens the agent's editor.
			case created(agentName: String)
			/// The session expired.
			case unauthorized
		}
	}

	private nonisolated enum CancelID: Hashable {
		case create
	}

	@Dependency(HomerAgentsClient.self)
	private var agentsClient

	@Dependency(\.dismiss)
	private var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding(\.name):
				// Typing clears the name's error, as in the console; the server's stays until the
				// next try.
				state.nameError = nil
				return .none

			case .binding:
				return .none

			case .createTapped:
				guard !state.isCreating else {
					return .none
				}
				state.nameError = Self.nameError(state.name)
				guard state.nameError == nil else {
					return .none
				}
				state.isCreating = true
				state.createError = nil
				return .run { [baseURL = state.baseURL, name = state.name] send in
					await send(.createFinished(name: name, Result { try await agentsClient.create(baseURL, name) }))
				}
				.cancellable(id: CancelID.create, cancelInFlight: true)

			case let .createFinished(_, .success(agentName)):
				state.isCreating = false
				return .send(.delegate(.created(agentName: agentName)))

			case let .createFinished(name, .failure(error)):
				state.isCreating = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.createError = Self.createErrorMessage(error, name: name)
				return .none

			case .cancelTapped:
				return .run { _ in
					await dismiss()
				}

			case .delegate:
				return .none
			}
		}
	}

	/// The console's `validateAgentName`: letters, digits, dashes and underscores. The server
	/// checks again and says why in a 400.
	static func nameError(_ name: String) -> String? {
		if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return "Name is required"
		}
		let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
		guard name.unicodeScalars.allSatisfy(allowed.contains) else {
			return "Use letters, digits, dashes, or underscores only"
		}
		return nil
	}

	static func createErrorMessage(_ error: any Error, name: String) -> String {
		switch error as? HomerAPIError {
		case .conflict, .server(status: 409, _):
			"An agent named \"\(name)\" already exists"
		default:
			error.localizedDescription
		}
	}
}
