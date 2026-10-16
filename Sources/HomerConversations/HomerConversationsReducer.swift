import ComposableArchitecture
import Foundation
import HomerCore

/// The Chat page of one instance: the conversations its proxy recorded — Slack threads the
/// connector ran a workflow in, and conversations started here — one of them open, with a
/// composer that starts or continues one the way a Slack mention does. The proxy's event stream
/// keeps it current; while that is down the page polls instead.
@Reducer
public struct HomerConversationsReducer: Sendable {
	static let reconnectDelay: Duration = .seconds(1)
	static let maxReconnectDelay: Duration = .seconds(30)
	/// How often the list and the open conversation are re-read while the event stream is down.
	package static let fallbackPollInterval: Duration = .seconds(10)
	package static let pageSize = 50
	/// The most the proxy answers in one page.
	package static let maxPageSize = 200

	static let tokenRejectedMessage = "The proxy rejected the token. Enter the proxy’s URL and a valid token to connect again."

	@ObservableState
	public struct State: Equatable {
		/// The Homer instance, which is what the proxy settings are keyed by.
		public let baseURL: String
		/// The proxy connected to this instance; nil shows the connect form in the page's place.
		public internal(set) var proxy: HomerProxySettings?
		/// The connect form: the page itself while no proxy is connected, a sheet over it
		/// otherwise (Proxy…).
		public var setup: HomerProxyConnectReducer.State?
		/// Who the proxy says this is (`GET /me`), the author of what is sent from here.
		public internal(set) var accountName: String?
		public internal(set) var workflows: [HomerWorkflow] = []

		public internal(set) var conversations: IdentifiedArrayOf<HomerConversation> = []
		/// Reaches the conversations older than the ones loaded; nil when there are none.
		public internal(set) var nextCursor: String?
		public internal(set) var hasLoaded = false
		/// The last list refresh's failure; the last good list stays on screen under it.
		public internal(set) var loadError: String?

		public var selectedConversationID: HomerConversation.ID?
		public internal(set) var thread: HomerConversationThread?
		public internal(set) var isLoadingThread = false
		public internal(set) var threadError: String?

		public var draft = ""
		/// The workflow a new conversation runs; `""` is the default workflow.
		public var selectedWorkflowCommand = ""
		public internal(set) var isSending = false
		public internal(set) var sendError: String?

		/// The event stream is open.
		public internal(set) var isLive = false
		/// The last event's id, what a reconnect resumes from.
		var lastEventID: String?
		/// The stream dropped since the last `.connected`: what it missed is re-read when it is
		/// back.
		var needsResync = false
		/// Between `shown` and `hidden`. An answer arriving outside it is dropped.
		var isShown = false

		public init(baseURL: String) {
			self.baseURL = baseURL
		}

		public var canSend: Bool {
			proxy != nil && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}

		/// The composer picks a workflow only for a new conversation; a follow-up continues the
		/// conversation's own.
		public var picksWorkflow: Bool {
			selectedConversationID == nil && workflows.count > 1
		}

		/// The open conversation's messages and runs in one sequence, by time — a run right after
		/// the message that started it.
		public var timeline: [TimelineItem] {
			guard let thread else {
				return []
			}
			let items = thread.messages.map(TimelineItem.message) + thread.runs.map(TimelineItem.run)
			return items.sorted { lhs, rhs in
				if lhs.time != rhs.time {
					return lhs.time < rhs.time
				}
				return lhs.order < rhs.order
			}
		}
	}

	public enum TimelineItem: Equatable, Sendable, Identifiable {
		case message(HomerConversationMessage)
		case run(HomerConversationRun)

		public var id: String {
			switch self {
			case let .message(message):
				"message-\(message.id)"
			case let .run(run):
				"run-\(run.id)"
			}
		}

		var time: Double {
			switch self {
			case let .message(message):
				message.createdAt
			case let .run(run):
				run.startedAt
			}
		}

		/// Messages before runs at the same instant, and each by id.
		var order: (Int, Int) {
			switch self {
			case let .message(message):
				(0, message.id)
			case let .run(run):
				(1, run.id)
			}
		}
	}

	/// What the page needs before anything else, fetched together.
	public struct Bootstrap: Equatable, Sendable {
		public var user: HomerProxyUser
		public var workflows: [HomerWorkflow]

		public init(user: HomerProxyUser, workflows: [HomerWorkflow]) {
			self.user = user
			self.workflows = workflows
		}
	}

	public enum SendOutcome: Equatable, Sendable {
		case created(HomerConversationCreated)
		case replied(id: HomerConversation.ID, HomerConversationReply)
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// The page came on screen; it follows the proxy until `hidden`.
		case shown
		case hidden
		/// The header's Refresh: re-reads everything on screen.
		case refreshTapped

		case bootstrapLoaded(Result<Bootstrap, any Error>)
		case conversationsLoaded(Result<HomerConversationPage, any Error>, append: Bool)
		case loadMoreTapped
		case threadLoaded(id: HomerConversation.ID, Result<HomerConversationThread, any Error>)

		case newConversationTapped
		case sendTapped
		case sendFinished(Result<SendOutcome, any Error>)

		case event(HomerConversationEvent)
		/// The stream ended or failed; `failure` is why, nil when the server closed it.
		case streamDropped(failure: String?)
		/// The fallback poll's tick.
		case pollTick
		/// The proxy answered 401: the token is not known any more.
		case proxyRejected

		case runTapped(processId: Int)
		case changeProxyTapped
		case disconnectTapped
		case setup(HomerProxyConnectReducer.Action)
		case delegate(Delegate)

		/// What the instance does for the page. A proxy failure never signs the instance out:
		/// there is no `unauthorized` here by design.
		@CasePathable
		public enum Delegate: Equatable, Sendable {
			case openProcess(processId: Int)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case bootstrap
		case list
		case thread
		case events
		case fallbackPolling
		case send
	}

	@Dependency(HomerConversationsClient.self)
	private var client

	@Dependency(HomerProxySettingsClient.self)
	private var settings

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		// One reducer, so `onChange` below sees the selection a binding writes.
		CombineReducers {
			BindingReducer()
			Reduce { state, action in
				switch action {
				case .binding:
					return .none

				case .shown:
					state.isShown = true
					state.proxy = settings.load(state.baseURL)
					guard state.proxy != nil else {
						if state.setup == nil {
							state.setup = HomerProxyConnectReducer.State()
						}
						return .none
					}
					return start(&state)

				case .hidden:
					state.isShown = false
					state.isLive = false
					return cancelAll()

				case .refreshTapped:
					guard state.isShown, state.proxy != nil else {
						return .none
					}
					return .merge(loadBootstrap(state), loadConversations(state, append: false), loadThread(state))

				case let .bootstrapLoaded(.success(bootstrap)):
					guard state.isShown else {
						return .none
					}
					state.accountName = bootstrap.user.name
					state.workflows = bootstrap.workflows
					if !bootstrap.workflows.contains(where: { $0.command == state.selectedWorkflowCommand }) {
						state.selectedWorkflowCommand = bootstrap.workflows.first(where: \.isDefault)?.command
							?? bootstrap.workflows.first?.command ?? ""
					}
					return .none

				case let .bootstrapLoaded(.failure(error)):
					return failed(&state, error) { state, message in
						state.loadError = message
					}

				case let .conversationsLoaded(.success(page), append):
					guard state.isShown else {
						return .none
					}
					if append {
						for conversation in page.items where state.conversations[id: conversation.id] == nil {
							state.conversations.append(conversation)
						}
					}
					else {
						state.conversations = IdentifiedArray(page.items, uniquingIDsWith: { first, _ in first })
					}
					state.nextCursor = page.nextCursor
					sortConversations(&state)
					state.hasLoaded = true
					state.loadError = nil
					return .none

				case let .conversationsLoaded(.failure(error), _):
					return failed(&state, error) { state, message in
						state.loadError = message
					}

				case .loadMoreTapped:
					guard state.nextCursor != nil else {
						return .none
					}
					return loadConversations(state, append: true)

				case let .threadLoaded(id, result):
					// Another conversation was opened meanwhile: this answer is not its.
					guard state.isShown, state.selectedConversationID == id else {
						return .none
					}
					state.isLoadingThread = false
					switch result {
					case let .success(thread):
						state.thread = thread
						state.threadError = nil
						upsert(thread.conversation, in: &state)
						return .none
					case let .failure(error):
						return failed(&state, error) { state, message in
							state.threadError = message
						}
					}

				case .newConversationTapped:
					state.selectedConversationID = nil
					state.thread = nil
					state.threadError = nil
					state.sendError = nil
					return .none

				case .sendTapped:
					guard state.canSend, let proxy = state.proxy else {
						return .none
					}
					let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
					state.isSending = true
					state.sendError = nil
					if let id = state.selectedConversationID {
						return .run { send in
							await send(.sendFinished(Result { try await .replied(id: id, client.reply(proxy, id, text)) }))
						}
						.cancellable(id: CancelID.send, cancelInFlight: true)
					}
					let command = state.selectedWorkflowCommand
					return .run { send in
						await send(.sendFinished(Result { try await .created(client.create(proxy, command, text)) }))
					}
					.cancellable(id: CancelID.send, cancelInFlight: true)

				case let .sendFinished(.success(outcome)):
					state.isSending = false
					state.draft = ""
					switch outcome {
					case let .created(created):
						upsert(created.conversation, in: &state)
						// The thread is set before the selection, so the selection's `onChange` finds
						// it already showing this conversation and does not re-read it.
						state.thread = HomerConversationThread(
							conversation: created.conversation,
							messages: [created.message],
							runs: [created.run]
						)
						state.threadError = nil
						state.selectedConversationID = created.conversation.id
					case let .replied(id, reply):
						guard state.selectedConversationID == id else {
							return .none
						}
						append(reply.message, to: &state)
						upsert(reply.run, in: &state)
					}
					return .none

				case let .sendFinished(.failure(error)):
					state.isSending = false
					return failed(&state, error) { state, message in
						state.sendError = message
					}

				case let .event(event):
					guard state.isShown else {
						return .none
					}
					if let id = event.id {
						state.lastEventID = id
					}
					switch event.kind {
					case .connected:
						state.isLive = true
						let resync = state.needsResync
						state.needsResync = false
						return .merge(
							.cancel(id: CancelID.fallbackPolling),
							resync ? .merge(loadConversations(state, append: false), loadThread(state)) : .none
						)
					case .reset:
						return .merge(loadConversations(state, append: false), loadThread(state))
					case let .conversationCreated(conversation), let .conversationUpdated(conversation):
						upsert(conversation, in: &state)
						return .none
					case let .messageCreated(message):
						guard message.conversationId == state.selectedConversationID else {
							return .none
						}
						append(message, to: &state)
						return .none
					case let .runUpdated(run):
						guard run.conversationId == state.selectedConversationID else {
							return .none
						}
						upsert(run, in: &state)
						return .none
					}

				case let .streamDropped(failure):
					guard state.isShown else {
						return .none
					}
					state.isLive = false
					state.needsResync = true
					if let failure {
						state.loadError = failure
					}
					return pollWhileDown()

				case .pollTick:
					guard state.isShown, state.proxy != nil else {
						return .none
					}
					return .merge(loadConversations(state, append: false), loadThread(state))

				case .proxyRejected:
					let url = state.proxy?.url ?? ""
					clearData(&state)
					state.proxy = nil
					state.setup = HomerProxyConnectReducer.State(url: url, message: Self.tokenRejectedMessage)
					return cancelAll()

				case let .runTapped(processId):
					return .send(.delegate(.openProcess(processId: processId)))

				case .changeProxyTapped:
					guard let proxy = state.proxy else {
						return .none
					}
					state.setup = HomerProxyConnectReducer.State(url: proxy.url)
					return .none

				case .disconnectTapped:
					settings.remove(state.baseURL)
					clearData(&state)
					state.proxy = nil
					state.setup = HomerProxyConnectReducer.State()
					return cancelAll()

				case let .setup(.delegate(.connected(proxy, name))):
					settings.save(state.baseURL, proxy)
					clearData(&state)
					state.proxy = proxy
					state.setup = nil
					state.accountName = name
					// What `start` restarts cancels its own earlier run (`cancelInFlight`); the rest is
					// cancelled here — a cancel of an id merged with its restart could land after it.
					return .merge(
						.cancel(id: CancelID.fallbackPolling),
						.cancel(id: CancelID.send),
						state.isShown ? start(&state) : .none
					)

				case .setup(.delegate(.cancelled)):
					// Inline, the form is the page: there is nothing to go back to.
					if state.proxy != nil {
						state.setup = nil
					}
					return .none

				case .setup:
					return .none

				case .delegate:
					return .none
				}
			}
		}
		.ifLet(\.setup, action: \.setup) {
			HomerProxyConnectReducer()
		}
		.onChange(of: \.selectedConversationID) { _, state in
			state.sendError = nil
			guard let id = state.selectedConversationID else {
				state.thread = nil
				state.threadError = nil
				return .cancel(id: CancelID.thread)
			}
			// Set together with the selection (a conversation just started here).
			if state.thread?.conversation.id == id {
				return .none
			}
			state.thread = nil
			state.threadError = nil
			return loadThread(state)
		}
	}

	// MARK: - Effects

	/// Everything the page does once a proxy is connected and it is on screen.
	private func start(_ state: inout State) -> Effect<Action> {
		.merge(loadBootstrap(state), loadConversations(state, append: false), loadThread(state), followEvents(state))
	}

	private func loadBootstrap(_ state: State) -> Effect<Action> {
		guard let proxy = state.proxy else {
			return .none
		}
		return .run { send in
			await send(.bootstrapLoaded(Result {
				async let user = client.me(proxy)
				async let workflows = client.workflows(proxy)
				return try await Bootstrap(user: user, workflows: workflows)
			}))
		}
		.cancellable(id: CancelID.bootstrap, cancelInFlight: true)
	}

	/// The first page again (as many as are loaded, so a refresh keeps every row current), or
	/// the next page after the last.
	private func loadConversations(_ state: State, append: Bool) -> Effect<Action> {
		guard let proxy = state.proxy else {
			return .none
		}
		let limit = append ? Self.pageSize : min(Self.maxPageSize, max(Self.pageSize, state.conversations.count))
		let cursor = append ? state.nextCursor : nil
		return .run { send in
			await send(.conversationsLoaded(Result { try await client.conversations(proxy, limit, cursor) }, append: append))
		}
		.cancellable(id: CancelID.list, cancelInFlight: true)
	}

	private func loadThread(_ state: State) -> Effect<Action> {
		guard let proxy = state.proxy, let id = state.selectedConversationID else {
			return .none
		}
		return .run { send in
			await send(.threadLoaded(id: id, Result { try await client.conversation(proxy, id) }))
		}
		.cancellable(id: CancelID.thread, cancelInFlight: true)
	}

	/// Follows the proxy's events, reconnecting from the last event's id when the stream
	/// drops, with a doubling wait. A rejected token ends it.
	private func followEvents(_ state: State) -> Effect<Action> {
		guard let proxy = state.proxy else {
			return .none
		}
		return .run { [lastEventID = state.lastEventID] send in
			var lastEventID = lastEventID
			var failures = 0
			while true {
				do {
					for try await event in client.events(proxy, lastEventID) {
						if let id = event.id {
							lastEventID = id
						}
						if event.kind == .connected {
							failures = 0
						}
						await send(.event(event))
					}
					await send(.streamDropped(failure: nil))
				}
				catch HomerAPIError.unauthorized {
					await send(.proxyRejected)
					return
				}
				catch {
					failures += 1
					await send(.streamDropped(failure: error.localizedDescription))
				}
				let delay = Self.reconnectDelay * (1 << min(failures, 5))
				try await clock.sleep(for: min(delay, Self.maxReconnectDelay))
			}
		}
		.cancellable(id: CancelID.events, cancelInFlight: true)
	}

	/// Re-reads the list and the open conversation on a cadence while the stream is down; the
	/// next `.connected` cancels it.
	private func pollWhileDown() -> Effect<Action> {
		.run { send in
			while true {
				try await clock.sleep(for: Self.fallbackPollInterval)
				await send(.pollTick)
			}
		}
		.cancellable(id: CancelID.fallbackPolling, cancelInFlight: true)
	}

	private func cancelAll() -> Effect<Action> {
		.merge(
			.cancel(id: CancelID.bootstrap),
			.cancel(id: CancelID.list),
			.cancel(id: CancelID.thread),
			.cancel(id: CancelID.events),
			.cancel(id: CancelID.fallbackPolling),
			.cancel(id: CancelID.send)
		)
	}

	// MARK: - State

	/// A failure of any call: a 401 means the proxy no longer knows the token, and the page
	/// gives way to the connect form; anything else is told where `report` puts it.
	private func failed(
		_ state: inout State,
		_ error: any Error,
		report: (inout State, String) -> Void
	) -> Effect<Action> {
		guard state.isShown else {
			return .none
		}
		if error as? HomerAPIError == .unauthorized {
			return .send(.proxyRejected)
		}
		report(&state, error.localizedDescription)
		return .none
	}

	private func upsert(_ conversation: HomerConversation, in state: inout State) {
		state.conversations[id: conversation.id] = conversation
		sortConversations(&state)
		if state.thread?.conversation.id == conversation.id {
			state.thread?.conversation = conversation
		}
	}

	private func append(_ message: HomerConversationMessage, to state: inout State) {
		guard state.thread?.conversation.id == message.conversationId,
		      state.thread?.messages.contains(where: { $0.id == message.id }) == false
		else {
			return
		}
		state.thread?.messages.append(message)
	}

	private func upsert(_ run: HomerConversationRun, in state: inout State) {
		guard state.thread?.conversation.id == run.conversationId else {
			return
		}
		if let index = state.thread?.runs.firstIndex(where: { $0.id == run.id }) {
			state.thread?.runs[index] = run
		}
		else {
			state.thread?.runs.append(run)
		}
	}

	/// Newest activity first, as the proxy lists them.
	private func sortConversations(_ state: inout State) {
		state.conversations.sort { lhs, rhs in
			if lhs.updatedAt != rhs.updatedAt {
				return lhs.updatedAt > rhs.updatedAt
			}
			return lhs.id > rhs.id
		}
	}

	/// Drops everything read from the proxy, for another proxy or none.
	private func clearData(_ state: inout State) {
		state.accountName = nil
		state.workflows = []
		state.conversations = []
		state.nextCursor = nil
		state.hasLoaded = false
		state.loadError = nil
		state.selectedConversationID = nil
		state.thread = nil
		state.isLoadingThread = false
		state.threadError = nil
		state.isSending = false
		state.sendError = nil
		state.isLive = false
		state.lastEventID = nil
		state.needsResync = false
	}
}
