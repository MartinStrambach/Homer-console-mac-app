import ComposableArchitecture
import Foundation
import HomerCore

/// The debug run sheet of one command (the console's `debug-run-dialog.tsx`): query params, run
/// through the agent's declared transformers, and environment variables, merged in verbatim.
/// A real run is created — with the agent's locks and parallel-run slots.
@Reducer
public struct HomerAgentDebugRunReducer: Sendable {
	@ObservableState
	public struct State: Equatable, Identifiable {
		public let baseURL: String
		public let agentName: String
		/// Zero-based; shown as "#\(commandIndex + 1)".
		public let commandIndex: Int
		/// The agent's declared inputs, for the hint under a param row that names one.
		public let inputs: [HomerAgent.Input]
		public var params: IdentifiedArrayOf<HomerKeyValue>
		public var env: IdentifiedArrayOf<HomerKeyValue>
		public internal(set) var isRunning = false
		public internal(set) var runError: String?

		public init(
			baseURL: String,
			agentName: String,
			commandIndex: Int,
			inputs: [HomerAgent.Input],
			params: [HomerKeyValue],
			env: [HomerKeyValue]
		) {
			self.baseURL = baseURL
			self.agentName = agentName
			self.commandIndex = commandIndex
			self.inputs = inputs
			self.params = IdentifiedArray(uniqueElements: params)
			self.env = IdentifiedArray(uniqueElements: env)
		}

		public var id: Int {
			commandIndex
		}

		/// The declared input a param row names, by its trimmed key.
		public func declaredInput(named key: String) -> HomerAgent.Input? {
			let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
			return inputs.first { $0.paramName == name }
		}

		public var request: HomerAgentDebugRequest {
			HomerAgentDebugRequest(commandIndex: commandIndex, env: Array(env), params: Array(params))
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case addParamTapped
		case removeParamTapped(id: HomerKeyValue.ID)
		case addEnvTapped
		case removeEnvTapped(id: HomerKeyValue.ID)
		case runTapped
		case runFinished(Result<Int, any Error>)
		case cancelTapped
		case delegate(Delegate)

		@CasePathable
		public enum Delegate: Equatable, Sendable {
			/// The run started; the rows are kept for the command's next run and its Recall.
			case started(processId: Int, env: [HomerKeyValue], params: [HomerKeyValue])
			case unauthorized
		}
	}

	nonisolated enum CancelID: Hashable {
		case run
	}

	@Dependency(HomerAgentEditorClient.self)
	private var editorClient

	@Dependency(\.uuid)
	private var uuid

	@Dependency(\.dismiss)
	private var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .addParamTapped:
				state.params.append(HomerKeyValue(id: uuid()))
				return .none

			case let .removeParamTapped(id):
				state.params.remove(id: id)
				return .none

			case .addEnvTapped:
				state.env.append(HomerKeyValue(id: uuid()))
				return .none

			case let .removeEnvTapped(id):
				state.env.remove(id: id)
				return .none

			case .runTapped:
				guard !state.isRunning else {
					return .none
				}
				state.isRunning = true
				state.runError = nil
				return .run { [baseURL = state.baseURL, agentName = state.agentName, request = state.request] send in
					await send(.runFinished(Result { try await editorClient.debug(baseURL, agentName, request) }))
				}
				.cancellable(id: CancelID.run, cancelInFlight: true)

			case let .runFinished(.success(processId)):
				state.isRunning = false
				return .send(.delegate(.started(processId: processId, env: Array(state.env), params: Array(state.params))))

			case let .runFinished(.failure(error)):
				state.isRunning = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.runError = error.localizedDescription
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
}
