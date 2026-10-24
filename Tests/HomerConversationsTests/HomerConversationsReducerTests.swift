import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerConversations
@testable import HomerCore
import Testing

@MainActor
@Suite("Homer conversations page", .dependencies)
struct HomerConversationsReducerTests {
	nonisolated private static let baseURL = "https://homer.example.com"
	nonisolated private static let proxy = HomerProxySettings(url: "https://proxy.example.com", token: "secret")

	private let workflow = HomerWorkflow(command: "", agent: "conversation", description: "Chat")
	private let other = HomerWorkflow(command: "ask", agent: "ask-web")
	private let slackConversation = HomerConversation(
		id: "1758445123.123456",
		origin: .slack,
		agent: "conversation",
		slackChannel: "C01",
		title: "from slack",
		createdAt: 100,
		updatedAt: 200
	)
	private let appConversation = HomerConversation(
		id: "app-1",
		origin: .app,
		agent: "conversation",
		title: "hello",
		createdAt: 150,
		updatedAt: 150
	)

	private func message(_ id: Int, in conversation: String, role: HomerConversationMessage.Role = .user, at time: Double) -> HomerConversationMessage {
		HomerConversationMessage(id: id, conversationId: conversation, runId: 1, role: role, author: role == .user ? "martin" : "conversation", text: "m\(id)", createdAt: time)
	}

	private func run(_ id: Int, in conversation: String, state: HomerConversationRun.State, at time: Double) -> HomerConversationRun {
		HomerConversationRun(id: id, conversationId: conversation, origin: .app, startedBy: "martin", agent: "conversation", processIds: [400 + id], state: state, startedAt: time, updatedAt: time)
	}

	/// The page on screen with a connected proxy and the Slack conversation open.
	private func shownState() -> HomerConversationsReducer.State {
		var state = HomerConversationsReducer.State(baseURL: Self.baseURL)
		state.isShown = true
		state.proxy = Self.proxy
		state.accountName = "martin"
		state.workflows = [workflow]
		state.conversations = [slackConversation, appConversation]
		state.hasLoaded = true
		state.selectedConversationID = slackConversation.id
		state.thread = HomerConversationThread(
			conversation: slackConversation,
			messages: [message(1, in: slackConversation.id, at: 100)],
			runs: [run(1, in: slackConversation.id, state: .running, at: 100)]
		)
		state.isLive = true
		return state
	}

	/// Holds a stubbed call until the test lets it answer, so answers of concurrent effects
	/// arrive in a known order.
	private struct Gate: Sendable {
		private let stream: AsyncStream<Void>
		private let continuation: AsyncStream<Void>.Continuation

		init() {
			(stream, continuation) = AsyncStream<Void>.makeStream()
		}

		func wait() async {
			for await _ in stream {
				return
			}
		}

		func open() {
			continuation.yield(())
		}
	}

	@Test("without a proxy, shown puts up the connect form and asks nothing")
	func shownWithoutProxy() async {
		let store = TestStore(initialState: HomerConversationsReducer.State(baseURL: Self.baseURL)) {
			HomerConversationsReducer()
		} withDependencies: {
			$0[HomerProxySettingsClient.self].load = { baseURL in
				#expect(baseURL == Self.baseURL)
				return nil
			}
		}

		await store.send(.shown) {
			$0.isShown = true
			$0.setup = HomerProxyConnectReducer.State()
		}
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("with a proxy, shown reads who this is, the workflows and the list, and follows the events until hidden")
	func shownWithProxy() async {
		let listGate = Gate()
		let events = LockIsolated<AsyncThrowingStream<HomerConversationEvent, any Error>.Continuation?>(nil)
		let resumedFrom = LockIsolated<String?>("unset")
		let store = TestStore(initialState: HomerConversationsReducer.State(baseURL: Self.baseURL)) {
			HomerConversationsReducer()
		} withDependencies: { [workflow, other, slackConversation] in
			$0.continuousClock = TestClock()
			$0[HomerProxySettingsClient.self].load = { _ in Self.proxy }
			$0[HomerConversationsClient.self].me = { _ in HomerProxyUser(name: "martin") }
			$0[HomerConversationsClient.self].workflows = { _ in [other, workflow] }
			$0[HomerConversationsClient.self].conversations = { _, limit, cursor in
				#expect(limit == HomerConversationsReducer.pageSize)
				#expect(cursor == nil)
				await listGate.wait()
				return HomerConversationPage(items: [slackConversation], nextCursor: "older")
			}
			$0[HomerConversationsClient.self].events = { _, lastEventID in
				resumedFrom.setValue(lastEventID)
				return AsyncThrowingStream { events.setValue($0) }
			}
		}

		await store.send(.shown) {
			$0.isShown = true
			$0.proxy = Self.proxy
		}
		await store.receive(\.bootstrapLoaded.success) {
			$0.accountName = "martin"
			$0.workflows = [other, workflow]
			// The default workflow is picked, wherever it is listed.
			$0.selectedWorkflowCommand = ""
		}
		listGate.open()
		await store.receive(\.conversationsLoaded) {
			$0.conversations = [slackConversation]
			$0.nextCursor = "older"
			$0.hasLoaded = true
		}
		while events.value == nil {
			await Task.yield()
		}
		#expect(resumedFrom.value == nil)

		events.value?.yield(HomerConversationEvent(id: nil, kind: .connected))
		await store.receive(\.event) {
			$0.isLive = true
		}
		// An event of another conversation only touches the list.
		let newer = HomerConversation(id: "app-9", origin: .app, agent: "conversation", title: "new", createdAt: 900, updatedAt: 900)
		events.value?.yield(HomerConversationEvent(id: "7", kind: .conversationCreated(newer)))
		await store.receive(\.event) {
			$0.conversations = [newer, slackConversation]
			$0.lastEventID = "7"
		}

		await store.send(.hidden) {
			$0.isShown = false
			$0.isLive = false
		}
	}

	@Test("opening a conversation reads it; an answer for another conversation is dropped")
	func selection() async {
		var state = shownState()
		state.selectedConversationID = nil
		state.thread = nil
		let thread = HomerConversationThread(conversation: appConversation, messages: [message(5, in: appConversation.id, at: 150)])
		let store = TestStore(initialState: state) {
			HomerConversationsReducer()
		} withDependencies: {
			$0[HomerConversationsClient.self].conversation = { _, id in
				#expect(id == "app-1")
				return thread
			}
		}

		await store.send(.binding(.set(\.selectedConversationID, appConversation.id))) {
			$0.selectedConversationID = "app-1"
		}
		await store.receive(\.threadLoaded) {
			$0.thread = thread
		}

		let stale = HomerConversationThread(conversation: slackConversation)
		await store.send(.threadLoaded(id: slackConversation.id, .success(stale)))

		await store.send(.binding(.set(\.selectedConversationID, nil))) {
			$0.selectedConversationID = nil
			$0.thread = nil
		}
	}

	@Test("Send with no conversation open starts one and opens it without re-reading it")
	func sendCreates() async {
		var state = shownState()
		state.selectedConversationID = nil
		state.thread = nil
		state.draft = "  hello there \n"
		let created = HomerConversationCreated(
			conversation: appConversation,
			message: message(5, in: appConversation.id, at: 150),
			run: run(5, in: appConversation.id, state: .queued, at: 150)
		)
		let store = TestStore(initialState: state) {
			HomerConversationsReducer()
		} withDependencies: {
			$0[HomerConversationsClient.self].create = { proxy, command, text in
				#expect(proxy == Self.proxy)
				#expect(command == "")
				#expect(text == "hello there")
				return created
			}
		}

		await store.send(.sendTapped) {
			$0.isSending = true
		}
		await store.receive(\.sendFinished.success) {
			$0.isSending = false
			$0.draft = ""
			$0.thread = HomerConversationThread(conversation: created.conversation, messages: [created.message], runs: [created.run])
			$0.selectedConversationID = "app-1"
		}
	}

	@Test("Send in an open conversation continues it, and the new turn shows at once")
	func sendReplies() async {
		var state = shownState()
		state.draft = "and then?"
		let reply = HomerConversationReply(
			message: message(2, in: slackConversation.id, at: 300),
			run: run(2, in: slackConversation.id, state: .queued, at: 300)
		)
		let store = TestStore(initialState: state) {
			HomerConversationsReducer()
		} withDependencies: { [slackConversation] in
			$0[HomerConversationsClient.self].reply = { _, id, text in
				#expect(id == slackConversation.id)
				#expect(text == "and then?")
				return reply
			}
		}

		await store.send(.sendTapped) {
			$0.isSending = true
		}
		await store.receive(\.sendFinished.success) {
			$0.isSending = false
			$0.draft = ""
			$0.thread?.messages.append(reply.message)
			$0.thread?.runs.append(reply.run)
		}
		// Nothing to send: the button is off, and the action does nothing.
		#expect(!store.state.canSend)
		await store.send(.sendTapped)
	}

	@Test("a failed send is told under the composer, and the draft is kept")
	func sendFails() async {
		var state = shownState()
		state.draft = "hi"
		let store = TestStore(initialState: state) {
			HomerConversationsReducer()
		} withDependencies: {
			$0[HomerConversationsClient.self].reply = { _, _, _ in throw HomerAPIError.server(status: 502, message: "Homer refused the run") }
		}

		await store.send(.sendTapped) {
			$0.isSending = true
		}
		await store.receive(\.sendFinished.failure) {
			$0.isSending = false
			$0.sendError = "Homer refused the run"
		}
	}

	@Test("events update the open conversation and the list; another conversation's turns only the list")
	func events() async {
		let store = TestStore(initialState: shownState()) {
			HomerConversationsReducer()
		}
		let id = slackConversation.id

		let answer = message(2, in: id, role: .assistant, at: 160)
		await store.send(.event(HomerConversationEvent(id: "10", kind: .messageCreated(answer)))) {
			$0.lastEventID = "10"
			$0.thread?.messages.append(answer)
		}
		// Twice is once.
		await store.send(.event(HomerConversationEvent(id: "11", kind: .messageCreated(answer)))) {
			$0.lastEventID = "11"
		}
		let elsewhere = message(9, in: appConversation.id, at: 170)
		await store.send(.event(HomerConversationEvent(id: "12", kind: .messageCreated(elsewhere)))) {
			$0.lastEventID = "12"
		}

		let finished = run(1, in: id, state: .finished, at: 100)
		await store.send(.event(HomerConversationEvent(id: "13", kind: .runUpdated(finished)))) {
			$0.lastEventID = "13"
			$0.thread?.runs = [finished]
		}

		var updated = slackConversation
		updated.updatedAt = 999
		updated.inFlight = false
		await store.send(.event(HomerConversationEvent(id: "14", kind: .conversationUpdated(updated)))) {
			$0.lastEventID = "14"
			$0.conversations[id: id] = updated
			$0.thread?.conversation = updated
		}
		// The list stays newest first.
		var app = appConversation
		app.updatedAt = 1000
		await store.send(.event(HomerConversationEvent(id: "15", kind: .conversationUpdated(app)))) {
			$0.lastEventID = "15"
			$0.conversations = [app, updated]
		}
		#expect(store.state.timeline.map(\.id) == ["message-1", "run-1", "message-2"])
	}

	@Test("while the stream is down the page polls, and re-reads once the stream is back")
	func fallbackPolling() async {
		let clock = TestClock()
		let threadGate = Gate()
		let listReads = LockIsolated(0)
		let threadReads = LockIsolated(0)
		let store = TestStore(initialState: shownState()) {
			HomerConversationsReducer()
		} withDependencies: { [slackConversation, appConversation] in
			$0.continuousClock = clock
			$0[HomerConversationsClient.self].conversations = { _, limit, _ in
				listReads.withValue { $0 += 1 }
				#expect(limit == HomerConversationsReducer.pageSize)
				return HomerConversationPage(items: [slackConversation, appConversation])
			}
			$0[HomerConversationsClient.self].conversation = { _, _ in
				threadReads.withValue { $0 += 1 }
				await threadGate.wait()
				return HomerConversationThread(conversation: slackConversation)
			}
		}
		let reread = HomerConversationThread(conversation: slackConversation)

		await store.send(.streamDropped(failure: "connection lost")) {
			$0.isLive = false
			$0.needsResync = true
			$0.loadError = "connection lost"
		}
		await clock.advance(by: HomerConversationsReducer.fallbackPollInterval)
		await store.receive(\.pollTick)
		await store.receive(\.conversationsLoaded) {
			$0.loadError = nil
		}
		threadGate.open()
		await store.receive(\.threadLoaded) {
			$0.thread = reread
		}
		#expect(listReads.value == 1)
		#expect(threadReads.value == 1)

		await store.send(.event(HomerConversationEvent(kind: .connected))) {
			$0.isLive = true
			$0.needsResync = false
		}
		await store.receive(\.conversationsLoaded)
		threadGate.open()
		await store.receive(\.threadLoaded)
		#expect(listReads.value == 2)

		// The poll is over.
		await clock.advance(by: HomerConversationsReducer.fallbackPollInterval * 3)
		#expect(listReads.value == 2)
	}

	@Test("a 401 from the proxy gives way to the connect form, keeps the saved settings and never signs Homer out")
	func rejectedToken() async {
		let store = TestStore(initialState: shownState()) {
			HomerConversationsReducer()
		}

		await store.send(.bootstrapLoaded(.failure(HomerAPIError.unauthorized)))
		await store.receive(\.proxyRejected) {
			$0.proxy = nil
			$0.setup = HomerProxyConnectReducer.State(url: Self.proxy.url, message: HomerConversationsReducer.tokenRejectedMessage)
			$0.accountName = nil
			$0.workflows = []
			$0.conversations = []
			$0.hasLoaded = false
			$0.selectedConversationID = nil
			$0.thread = nil
			$0.isLive = false
		}
	}

	@Test("connecting saves the settings for the instance and starts the page; disconnecting forgets them")
	func connectAndDisconnect() async {
		let listGate = Gate()
		let saved = LockIsolated<[String: HomerProxySettings]>([:])
		let removed = LockIsolated<[String]>([])
		var state = HomerConversationsReducer.State(baseURL: Self.baseURL)
		state.isShown = true
		state.setup = HomerProxyConnectReducer.State(url: Self.proxy.url, token: Self.proxy.token)
		let store = TestStore(initialState: state) {
			HomerConversationsReducer()
		} withDependencies: { [workflow] in
			$0.continuousClock = TestClock()
			$0[HomerProxySettingsClient.self].save = { baseURL, settings in saved.withValue { $0[baseURL] = settings } }
			$0[HomerProxySettingsClient.self].remove = { baseURL in removed.withValue { $0.append(baseURL) } }
			$0[HomerConversationsClient.self].me = { _ in HomerProxyUser(name: "martin") }
			$0[HomerConversationsClient.self].workflows = { _ in [workflow] }
			$0[HomerConversationsClient.self].conversations = { _, _, _ in
				await listGate.wait()
				return HomerConversationPage(items: [])
			}
			// A stream that never says anything; Disconnect closes it.
			$0[HomerConversationsClient.self].events = { _, _ in AsyncThrowingStream { _ in } }
		}

		await store.send(.setup(.delegate(.connected(Self.proxy, name: "martin")))) {
			$0.proxy = Self.proxy
			$0.setup = nil
			$0.accountName = "martin"
		}
		#expect(saved.value == [Self.baseURL: Self.proxy])
		await store.receive(\.bootstrapLoaded.success) {
			$0.workflows = [workflow]
		}
		listGate.open()
		await store.receive(\.conversationsLoaded) {
			$0.hasLoaded = true
		}

		await store.send(.disconnectTapped) {
			$0.proxy = nil
			$0.setup = HomerProxyConnectReducer.State()
			$0.accountName = nil
			$0.workflows = []
			$0.hasLoaded = false
		}
		#expect(removed.value == [Self.baseURL])
	}

	@Test("a run's number asks the instance to open the run")
	func runOpens() async {
		let store = TestStore(initialState: shownState()) {
			HomerConversationsReducer()
		}

		await store.send(.runTapped(processId: 401))
		await store.receive(\.delegate, .openProcess(processId: 401))
	}

	@Test("Load More appends the older page after the loaded ones")
	func loadMore() async {
		var state = shownState()
		state.nextCursor = "older"
		let older = HomerConversation(id: "app-0", origin: .app, agent: "conversation", title: "old", createdAt: 10, updatedAt: 10)
		let store = TestStore(initialState: state) {
			HomerConversationsReducer()
		} withDependencies: { [slackConversation] in
			$0[HomerConversationsClient.self].conversations = { _, limit, cursor in
				#expect(limit == HomerConversationsReducer.pageSize)
				#expect(cursor == "older")
				// One already shown comes again: it is not doubled.
				return HomerConversationPage(items: [slackConversation, older], nextCursor: nil)
			}
		}

		await store.send(.loadMoreTapped)
		await store.receive(\.conversationsLoaded) {
			$0.conversations.append(older)
			$0.nextCursor = nil
		}
		await store.send(.loadMoreTapped)
	}
}
