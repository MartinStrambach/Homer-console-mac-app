import ComposableArchitecture
import Foundation
import HomerCore

/// The form that connects an instance to its conversation proxy: the proxy's URL and this
/// user's token, checked with `GET /me` before they are kept.
@Reducer
public struct HomerProxyConnectReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public var url: String
		public var token: String
		public internal(set) var isConnecting = false
		/// Why the last attempt failed.
		public internal(set) var error: String?
		/// Why the form is shown, when it is not the first time: the proxy rejected the token.
		public var message: String?

		public init(url: String = "", token: String = "", message: String? = nil) {
			self.url = url
			self.token = token
			self.message = message
		}

		public var canConnect: Bool {
			!isConnecting
				&& !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				&& !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case connectTapped
		case connectFinished(HomerProxySettings, Result<HomerProxyUser, any Error>)
		case cancelTapped
		case delegate(Delegate)

		@CasePathable
		public enum Delegate: Equatable, Sendable {
			/// The proxy knows the token; `name` is who it says this is.
			case connected(HomerProxySettings, name: String)
			case cancelled
		}
	}

	static let invalidURLMessage = "Enter the proxy’s URL, starting with https:// or http://."
	static let unknownTokenMessage = "The proxy does not know this token."

	@Dependency(HomerConversationsClient.self)
	private var client

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .connectTapped:
				guard state.canConnect else {
					return .none
				}
				let url: String
				do {
					url = try HomerEndpoint.normalize(state.url)
				}
				catch {
					// The endpoint's own words name a Homer instance; this is the proxy's URL.
					state.error = Self.invalidURLMessage
					return .none
				}
				let settings = HomerProxySettings(url: url, token: state.token.trimmingCharacters(in: .whitespacesAndNewlines))
				state.isConnecting = true
				state.error = nil
				return .run { send in
					await send(.connectFinished(settings, Result { try await client.me(settings) }))
				}

			case let .connectFinished(settings, .success(user)):
				state.isConnecting = false
				state.url = settings.url
				return .send(.delegate(.connected(settings, name: user.name)))

			case let .connectFinished(_, .failure(error)):
				state.isConnecting = false
				state.error = error as? HomerAPIError == .unauthorized
					? Self.unknownTokenMessage
					: error.localizedDescription
				return .none

			case .cancelTapped:
				return .send(.delegate(.cancelled))

			case .delegate:
				return .none
			}
		}
	}
}
