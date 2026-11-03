import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerCore
@testable import HomerContinuations
import Testing

@MainActor
@Suite("Homer continuations and dispatches lists", .dependencies)
struct HomerContinuationsReducerTests {
	private static let baseURL = "https://homer.example.com"
	private let pending = HomerContinuation(
		id: 5,
		watchedProcessId: 12,
		status: .pending,
		agentName: "follow-up",
		originProcessId: 7,
		originAgentName: "starter",
		createdAt: 1_700_000_000
	)
	private let failed = HomerContinuation(
		id: 6,
		watchedProcessId: 13,
		status: .failed,
		agentName: "crash-report",
		originProcessId: 8,
		originAgentName: "factory",
		createdAt: 1_700_000_100,
		error: "boom"
	)
	private let dispatch = HomerDispatch(
		id: 3,
		questionId: "q-1",
		status: .pending,
		agentName: "deploy",
		answerParam: "APPROVAL",
		originProcessId: 40,
		originAgentName: "release",
		createdAt: 1_700_000_000
	)

	private func shownState() -> HomerContinuationListReducer.State {
		var state = HomerContinuationListReducer.State(baseURL: Self.baseURL)
		state.isShown = true
		state.pending = [pending]
		state.pendingTotal = 1
		state.failed = [failed]
		state.hasLoaded = true
		return state
	}

	/// The open view's two lists, from one stub.
	private func openLists(pending: [HomerContinuation], failed: [HomerContinuation]) -> @Sendable (
		String,
		HomerRecordQuery<HomerContinuationStatus>
	) async throws -> HomerRecordPage<HomerContinuation> {
		{ _, query in
			HomerRecordPage(items: query.status == .pending ? pending : failed)
		}
	}

	@Test("shown loads the pending and failed lists, and polls every 30 s until hidden")
	func shownPollsUntilHidden() async {
		let clock = TestClock()
		let queries = LockIsolated<[HomerRecordQuery<HomerContinuationStatus>]>([])
		let store = TestStore(initialState: HomerContinuationListReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationListReducer()
		} withDependencies: { [pending, failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { baseURL, query in
				#expect(baseURL == "https://homer.example.com")
				queries.withValue { $0.append(query) }
				return HomerRecordPage(items: query.status == .pending ? [pending] : [failed], total: query.status == .pending ? 3 : 1)
			}
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.loaded.success) {
			$0.pending = [pending]
			$0.pendingTotal = 3
			$0.failed = [failed]
			$0.hasLoaded = true
		}
		#expect(Set(queries.value.map(\.status)) == [.pending, .failed])
		#expect(queries.value.allSatisfy { $0.agentName == nil })

		await clock.advance(by: HomerContinuationListReducer.pollInterval)
		await store.receive(\.loaded.success)
		#expect(queries.value.count == 4)

		await store.send(.hidden) {
			$0.isShown = false
		}
		await clock.advance(by: .seconds(120))
		#expect(queries.value.count == 4)
	}

	@Test("the pending ones are listed soonest to expire first, those without an expiry last")
	func soonestFirst() async {
		let later = HomerContinuation(id: 1, watchedProcessId: 1, status: .pending, agentName: "a", originProcessId: 1, originAgentName: "o", expiresAt: 2000, createdAt: 30)
		let never = HomerContinuation(id: 2, watchedProcessId: 1, status: .pending, agentName: "a", originProcessId: 1, originAgentName: "o", createdAt: 20)
		let sooner = HomerContinuation(id: 3, watchedProcessId: 1, status: .pending, agentName: "a", originProcessId: 1, originAgentName: "o", expiresAt: 1000, createdAt: 10)
		var initialState = HomerContinuationListReducer.State(baseURL: Self.baseURL)
		initialState.isShown = true
		let store = TestStore(initialState: initialState) {
			HomerContinuationListReducer()
		}

		await store.send(.loaded(.success(.init(
			filter: .open,
			pending: HomerRecordPage(items: [later, never, sooner]),
			failed: HomerRecordPage(items: [])
		)))) {
			$0.pending = [sooner, later, never]
			$0.pendingTotal = 3
			$0.hasLoaded = true
		}
	}

	@Test("a status or agent filter reads the history, one page newest first, and Load More grows it")
	func historyFilters() async {
		let clock = TestClock()
		let queries = LockIsolated<[HomerRecordQuery<HomerContinuationStatus>]>([])
		let store = TestStore(initialState: shownState()) {
			HomerContinuationListReducer()
		} withDependencies: { [failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { _, query in
				queries.withValue { $0.append(query) }
				return HomerRecordPage(items: [failed], total: 150)
			}
		}

		await store.send(.filterChanged(.all)) {
			$0.filter = .all
			$0.pending = []
			$0.pendingTotal = 0
			$0.failed = []
			$0.hasLoaded = false
		}
		await store.receive(\.loaded.success) {
			$0.records = [failed]
			$0.total = 150
			$0.hasLoaded = true
		}
		#expect(queries.value.last == HomerRecordQuery(status: nil, agentName: nil, limit: 100))

		await store.send(.agentFilterChanged("crash-report")) {
			$0.agentFilter = "crash-report"
			$0.records = []
			$0.total = 0
			$0.hasLoaded = false
		}
		await store.receive(\.loaded.success) {
			$0.records = [failed]
			$0.total = 150
			$0.hasLoaded = true
		}
		#expect(queries.value.last == HomerRecordQuery(status: nil, agentName: "crash-report", limit: 100))

		await store.send(.filterChanged(.status(.failed))) {
			$0.filter = .status(.failed)
			$0.records = []
			$0.total = 0
			$0.hasLoaded = false
		}
		await store.receive(\.loaded.success) {
			$0.records = [failed]
			$0.total = 150
			$0.hasLoaded = true
		}
		#expect(queries.value.last == HomerRecordQuery(status: .failed, agentName: "crash-report", limit: 100))

		await store.send(.loadMoreTapped) {
			$0.limit = 200
		}
		await store.receive(\.loaded.success)
		#expect(queries.value.last == HomerRecordQuery(status: .failed, agentName: "crash-report", limit: 200))

		// A new filter starts from the first page again.
		await store.send(.filterChanged(.open)) {
			$0.filter = .open
			$0.limit = 100
			$0.records = []
			$0.total = 0
			$0.hasLoaded = false
		}
		await store.receive(\.loaded.success) {
			$0.pending = [failed]
			$0.pendingTotal = 150
			$0.failed = [failed]
			$0.hasLoaded = true
		}
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("an answer for filters since changed is dropped")
	func staleFilterAnswer() async {
		var initialState = shownState()
		initialState.filter = .all
		let store = TestStore(initialState: initialState) {
			HomerContinuationListReducer()
		}

		await store.send(.loaded(.success(.init(filter: .open, pending: HomerRecordPage(items: []), failed: HomerRecordPage(items: [])))))
		await store.send(.loaded(.success(.init(filter: .all, agentFilter: "other", records: HomerRecordPage(items: [])))))
	}

	@Test("a failed refresh keeps the last lists under an error, and the next one clears it")
	func failedRefreshKeepsData() async {
		let clock = TestClock()
		let fails = LockIsolated(true)
		let store = TestStore(initialState: shownState()) {
			HomerContinuationListReducer()
		} withDependencies: { [pending, failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { _, query in
				if fails.value {
					throw HomerAPIError.unreachable("offline")
				}
				return HomerRecordPage(items: query.status == .pending ? [pending] : [failed])
			}
		}

		await store.send(.shown)
		await store.receive(\.loaded.failure) {
			$0.loadError = HomerAPIError.unreachable("offline").localizedDescription
		}

		fails.setValue(false)
		await clock.advance(by: HomerContinuationListReducer.pollInterval)
		await store.receive(\.loaded.success) {
			$0.loadError = nil
		}
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a 401 asks the instance to sign out")
	func unauthorized() async {
		let store = TestStore(initialState: HomerContinuationListReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationListReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerContinuationsClient.self].continuations = { _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.loaded.failure)
		await store.receive(\.delegate, .unauthorized)
		// The instance answers with `hidden` (and replaces this state).
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("an answer landing after the list was hidden is dropped")
	func answerAfterHidden() async {
		let store = TestStore(initialState: HomerContinuationListReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationListReducer()
		}

		await store.send(.loaded(.success(.init(filter: .open, pending: HomerRecordPage(items: [pending]), failed: HomerRecordPage(items: [])))))
		await store.send(.loaded(.failure(HomerAPIError.unauthorized)))
	}

	@Test("cancel asks first, then cancels by id and refetches")
	func cancelFlow() async {
		let clock = TestClock()
		let cancelled = LockIsolated<[Int]>([])
		let store = TestStore(initialState: shownState()) {
			HomerContinuationListReducer()
		} withDependencies: { [failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].cancel = { baseURL, id in
				#expect(baseURL == "https://homer.example.com")
				cancelled.withValue { $0.append(id) }
			}
			$0[HomerContinuationsClient.self].continuations = openLists(pending: [], failed: [failed])
		}

		await store.send(.cancelTapped(id: 5)) {
			$0.alert = AlertState {
				TextState("Cancel this continuation?")
			} actions: {
				ButtonState(role: .destructive, action: .cancelConfirmed(id: 5)) {
					TextState("Yes, Cancel")
				}
				ButtonState(role: .cancel) {
					TextState("Keep Waiting")
				}
			} message: {
				TextState("This stops follow-up from starting when run #12 finishes. This cannot be undone.")
			}
		}
		await store.send(.alert(.presented(.cancelConfirmed(id: 5)))) {
			$0.alert = nil
			$0.cancellingIDs = [5]
		}
		await store.receive(\.cancelFinished) {
			$0.cancellingIDs = []
			$0.pending = []
		}
		// The instance re-reads the badge's count.
		await store.receive(\.delegate, .continuationsChanged)
		await store.receive(\.loaded.success) {
			$0.pendingTotal = 0
		}
		#expect(cancelled.value == [5])

		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a failed continuation offers no Cancel")
	func cancelOnlyPending() async {
		let store = TestStore(initialState: shownState()) {
			HomerContinuationListReducer()
		}

		await store.send(.cancelTapped(id: 6))
	}

	@Test("a cancel that comes too late says so on the card and refetches")
	func cancelConflict() async {
		let clock = TestClock()
		var initialState = shownState()
		initialState.cancellingIDs = [5]
		let store = TestStore(initialState: initialState) {
			HomerContinuationListReducer()
		} withDependencies: { [failed] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = openLists(pending: [], failed: [failed])
		}

		await store.send(.cancelFinished(id: 5, .failure(HomerAPIError.conflict))) {
			$0.cancellingIDs = []
			$0.cancelErrors = [5: HomerContinuationKind.notCancellableMessage]
		}
		await store.receive(\.delegate, .continuationsChanged)
		// The continuation fired meanwhile: it and its error leave the page.
		await store.receive(\.loaded.success) {
			$0.pending = []
			$0.pendingTotal = 0
			$0.cancelErrors = [:]
		}
		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a cancel answering 401 asks the instance to sign out")
	func cancelUnauthorized() async {
		var initialState = shownState()
		initialState.cancellingIDs = [5]
		let store = TestStore(initialState: initialState) {
			HomerContinuationListReducer()
		}

		await store.send(.cancelFinished(id: 5, .failure(HomerAPIError.unauthorized))) {
			$0.cancellingIDs = []
		}
		await store.receive(\.delegate, .unauthorized)
	}

	@Test("a run number opens the run's page")
	func processTapped() async {
		let store = TestStore(initialState: shownState()) {
			HomerContinuationListReducer()
		}

		await store.send(.processTapped(processId: 12))
		await store.receive(\.delegate, .openProcess(processId: 12))
	}

	@Test("cancelling a dispatch expires its question: the instance re-reads the open questions")
	func cancelDispatch() async {
		let clock = TestClock()
		let cancelled = LockIsolated<[Int]>([])
		var initialState = HomerDispatchListReducer.State(baseURL: Self.baseURL)
		initialState.isShown = true
		initialState.pending = [dispatch]
		initialState.pendingTotal = 1
		initialState.hasLoaded = true
		let store = TestStore(initialState: initialState) {
			HomerDispatchListReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].cancelDispatch = { _, id in
				cancelled.withValue { $0.append(id) }
			}
			$0[HomerContinuationsClient.self].dispatches = { _, _ in HomerRecordPage(items: []) }
		}

		await store.send(.cancelTapped(id: 3)) {
			$0.alert = AlertState {
				TextState("Cancel this dispatch?")
			} actions: {
				ButtonState(role: .destructive, action: .cancelConfirmed(id: 3)) {
					TextState("Yes, Cancel")
				}
				ButtonState(role: .cancel) {
					TextState("Keep Waiting")
				}
			} message: {
				TextState("The question run #40 asked expires, and deploy never starts. This cannot be undone.")
			}
		}
		await store.send(.alert(.presented(.cancelConfirmed(id: 3)))) {
			$0.alert = nil
			$0.cancellingIDs = [3]
		}
		await store.receive(\.cancelFinished) {
			$0.cancellingIDs = []
			$0.pending = []
		}
		await store.receive(\.delegate, .questionsChanged)
		await store.receive(\.loaded.success) {
			$0.pendingTotal = 0
		}
		#expect(cancelled.value == [3])
		await store.send(.hidden) {
			$0.isShown = false
		}
	}
}

@MainActor
@Suite("Homer continuations page", .dependencies)
struct HomerContinuationsPageTests {
	private static let baseURL = "https://homer.example.com"
	private let dispatch = HomerDispatch(
		id: 3,
		questionId: "q-1",
		status: .pending,
		agentName: "deploy",
		originProcessId: 40,
		originAgentName: "release",
		createdAt: 1_700_000_000
	)

	@Test("only the section on screen polls; switching hides one and shows the other")
	func sections() async {
		let clock = TestClock()
		let store = TestStore(initialState: HomerContinuationsReducer.State(baseURL: Self.baseURL)) {
			HomerContinuationsReducer()
		} withDependencies: { [dispatch] in
			$0.continuousClock = clock
			$0[HomerContinuationsClient.self].continuations = { _, _ in HomerRecordPage(items: []) }
			$0[HomerContinuationsClient.self].dispatches = { _, query in
				HomerRecordPage(items: query.status == .pending ? [dispatch] : [])
			}
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.continuations.shown) {
			$0.continuations.isShown = true
		}
		await store.receive(\.continuations.loaded.success) {
			$0.continuations.hasLoaded = true
		}

		await store.send(.sectionChanged(.dispatches)) {
			$0.section = .dispatches
		}
		await store.receive(\.continuations.hidden) {
			$0.continuations.isShown = false
		}
		await store.receive(\.dispatches.shown) {
			$0.dispatches.isShown = true
		}
		await store.receive(\.dispatches.loaded.success) {
			$0.dispatches.pending = [dispatch]
			$0.dispatches.pendingTotal = 1
			$0.dispatches.hasLoaded = true
		}

		await store.send(.refreshTapped)
		await store.receive(\.dispatches.refreshTapped)
		await store.receive(\.dispatches.loaded.success)

		await store.send(.hidden) {
			$0.isShown = false
		}
		await store.receive(\.dispatches.hidden) {
			$0.dispatches.isShown = false
		}
	}

	@Test("a card's detail is read again, opens a run in the page's place, and hands Cancel to its list")
	func detail() async {
		let fresh = HomerDispatch(
			id: 3,
			questionId: "q-1",
			status: .pending,
			agentName: "deploy",
			answerParam: "APPROVAL",
			params: ["ENV": "prod"],
			originProcessId: 40,
			originAgentName: "release",
			expiresAt: 1_700_003_600,
			createdAt: 1_700_000_000
		)
		var initialState = HomerContinuationsReducer.State(baseURL: Self.baseURL)
		initialState.section = .dispatches
		initialState.dispatches.pending = [dispatch]
		initialState.dispatches.hasLoaded = true
		let store = TestStore(initialState: initialState) {
			HomerContinuationsReducer()
		} withDependencies: {
			$0[HomerContinuationsClient.self].dispatch = { baseURL, id in
				#expect(baseURL == "https://homer.example.com")
				#expect(id == 3)
				return fresh
			}
		}

		await store.send(.recordTapped(.dispatch(dispatch))) {
			$0.detail = HomerRecordDetailReducer.State(baseURL: Self.baseURL, record: .dispatch(dispatch))
		}
		await store.send(\.detail.task) {
			$0.detail?.isLoading = true
		}
		await store.receive(\.detail.loaded.success) {
			$0.detail?.isLoading = false
			$0.detail?.record = .dispatch(fresh)
		}

		await store.send(\.detail.cancelTapped)
		await store.receive(\.detail.delegate) {
			$0.detail = nil
		}
		await store.receive(\.dispatches.cancelTapped) {
			$0.dispatches.alert = AlertState {
				TextState("Cancel this dispatch?")
			} actions: {
				ButtonState(role: .destructive, action: .cancelConfirmed(id: 3)) {
					TextState("Yes, Cancel")
				}
				ButtonState(role: .cancel) {
					TextState("Keep Waiting")
				}
			} message: {
				TextState("The question run #40 asked expires, and deploy never starts. This cannot be undone.")
			}
		}
		await store.send(\.dispatches.alert.dismiss) {
			$0.dispatches.alert = nil
		}

		await store.send(.recordTapped(.dispatch(dispatch))) {
			$0.detail = HomerRecordDetailReducer.State(baseURL: Self.baseURL, record: .dispatch(dispatch))
		}
		await store.send(\.detail.processTapped, 40)
		await store.receive(\.detail.delegate) {
			$0.detail = nil
		}
		await store.receive(\.delegate, .openProcess(processId: 40))
	}
}
