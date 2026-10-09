import ComposableArchitecture
import Foundation
import HomerAgents
import HomerContinuations
import HomerCore
import HomerCosts
import HomerProcessDetail
import HomerSignIn

/// One Homer instance of the console: its session, sign-in form, process list, open
/// questions and other pages. A process opens natively in `processDetail`; a page of the web
/// console (the header's Safari button, the graph of a workflow whose server sends only
/// Mermaid) opens in `webPage`. `HomerConsoleReducer` holds one per instance, all live at once:
/// switching shows another's last data straight away.
@Reducer
public struct HomerInstanceReducer: Sendable {
	static let pageSize = HomerProcessListing.pageSize
	static let processPollInterval = HomerProcessListing.pollInterval
	/// The console's own refresh cadence for questions (`useQuestions`).
	static let questionPollInterval: Duration = .seconds(30)
	/// The console reads `/health` again when the processes page mounts once a minute has
	/// passed (`useHealth`'s `staleTime`); here it is polled at that pace while the page is on
	/// screen.
	static let healthPollInterval: Duration = .seconds(60)
	/// The console's Flow cells refresh on this cadence too (`useFlowSummary`).
	static let flowSummaryPollInterval: Duration = .seconds(30)
	/// Root rows whose Flow cell is summarized, in list order. Each cell is one request, so the
	/// count is bounded rather than growing with "Load more" — the console caps it the same.
	static let flowSummaryRowLimit = 20

	public enum Session: Equatable, Sendable {
		/// Asking `/auth/me` whether the stored cookie is still a session.
		case checking
		case signedOut
		case signedIn(HomerUser)
	}

	@ObservableState
	public struct State: Equatable, Identifiable {
		public let baseURL: String
		public internal(set) var session: Session = .checking
		/// Shown while signed out.
		public var signIn: HomerSignInReducer.State

		// Processes
		public internal(set) var processes: IdentifiedArrayOf<HomerProcess> = []
		public internal(set) var processTotal = 0
		public internal(set) var processLimit = HomerInstanceReducer.pageSize
		public internal(set) var statusFilter: Set<HomerProcessStatus> = []
		public var rootsOnly = false
		public internal(set) var agentFilter: String?
		/// Runs must carry every tag listed; a tag chip in a row adds itself.
		public internal(set) var tagFilter: [String] = []
		/// The direct children of one run. Overrides `rootsOnly`, as in the console: a run's
		/// children are never roots.
		public internal(set) var parentFilter: Int?
		public internal(set) var oldestFirst = false
		/// The agent filter's choices.
		public internal(set) var agentNames: [String] = []
		public internal(set) var hasLoadedProcesses = false
		public internal(set) var processesError: String?
		public internal(set) var flowSummaries: [HomerProcess.ID: HomerFlowSummary] = [:]
		/// The roots `flowSummaries` covers: the first rows of the root view.
		var flowSummaryRootIDs: [HomerProcess.ID] = []
		/// Kill or retry requests still waiting on the server.
		public internal(set) var processActionsInFlight: Set<HomerProcess.ID> = []
		@Presents
		public var alert: AlertState<Action.Alert>?

		// Questions
		public internal(set) var questions: IdentifiedArrayOf<HomerQuestion> = []
		public internal(set) var hasLoadedQuestions = false
		public internal(set) var questionsError: String?
		public internal(set) var answerDrafts: [HomerQuestion.ID: String] = [:]
		/// Questions with an answer or a cancel still waiting on the server.
		public internal(set) var answeringQuestionIDs: Set<HomerQuestion.ID> = []
		/// Why an answer or a cancel failed.
		public internal(set) var answerErrors: [HomerQuestion.ID: String] = [:]
		/// The ask-and-dispatch question whose Cancel is waiting to be confirmed.
		public internal(set) var questionToCancel: HomerQuestion.ID?
		/// Every question of the run on screen in `processDetail`, open or not; nil until read.
		public internal(set) var runQuestions: HomerRunQuestions?

		// Health
		/// The last orphan pod sweep, shown above the process list when the instance has a
		/// Kubernetes runner.
		public internal(set) var sweep: HomerHealth.Sweep?
		/// The server's Homer version (`/heartbeat`), read once.
		public internal(set) var homerVersion: String?

		// Continuations
		/// The Continuations page's badge: how many continuations wait for their watched run.
		/// Polled only while the instance is on screen — the page picker is all that shows it.
		var pendingContinuations: Int?

		// The other pages
		/// The console's page, whichever instance is on screen (the console keeps it current).
		public internal(set) var page: HomerConsoleReducer.Tab = .processes
		public var continuations: HomerContinuationsReducer.State
		public var agents: HomerAgentsReducer.State
		public var costs: HomerCostsReducer.State
		/// The page reducer told it is on screen, so it polls.
		var shownChildPage: HomerChildPage?

		public var webPage: HomerWebPage?
		/// A run's page, over whichever page opened it.
		@Presents
		public var processDetail: HomerProcessDetailReducer.State?

		/// Whether this instance is the one on screen. Its processes are polled only then; the
		/// questions of every signed-in instance always, for the badges.
		var isActive = false

		public init(baseURL: String) {
			self.baseURL = baseURL
			@Shared(.homerUsernames) var usernames
			self.signIn = HomerSignInReducer.State(baseURL: baseURL, username: usernames[baseURL] ?? "")
			self.continuations = HomerContinuationsReducer.State(baseURL: baseURL)
			self.agents = HomerAgentsReducer.State(baseURL: baseURL)
			self.costs = HomerCostsReducer.State(baseURL: baseURL)
		}

		public var id: String {
			baseURL
		}

		public var user: HomerUser? {
			if case let .signedIn(user) = session {
				return user
			}
			return nil
		}

		public var openQuestionCount: Int {
			user == nil ? 0 : questions.count
		}

		public var pendingContinuationCount: Int {
			user == nil ? 0 : pendingContinuations ?? 0
		}

		public var canLoadMoreProcesses: Bool {
			processes.count < processTotal
		}

		/// The root view shows a Flow column; a parent filter turns it back into a plain list.
		public var showsFlowColumn: Bool {
			rootsOnly && parentFilter == nil
		}

		public var hasActiveFilters: Bool {
			!statusFilter.isEmpty || agentFilter != nil || !tagFilter.isEmpty || parentFilter != nil
		}

		/// What the listed runs cost together — the rows shown, not every match, as in the
		/// console's "Total cost".
		public var listedCostUsd: Double {
			processes.reduce(0) { $0 + ($1.costUsd ?? 0) }
		}

		var processQuery: HomerProcessQuery {
			HomerProcessQuery(
				statuses: statusFilter,
				rootsOnly: showsFlowColumn,
				agentName: agentFilter,
				tags: tagFilter,
				parentProcessId: parentFilter,
				oldestFirst: oldestFirst,
				limit: processLimit
			)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// Once per launch: checks whether the stored session cookie is still valid.
		case start
		case sessionChecked(Result<HomerUser, any Error>)
		/// The instance came on screen, or went off it.
		case activated
		case deactivated

		case signIn(HomerSignInReducer.Action)
		/// Signed in from elsewhere: the "Add Instance" form, given this instance's URL.
		case signedIn(HomerUser)
		case signOutTapped

		case refreshTapped
		/// The console's page changed. The questions page coming on screen shows the server's
		/// answer of now, not of up to 30 s ago.
		case pageChanged(HomerConsoleReducer.Tab)
		case statusFilterToggled(HomerProcessStatus)
		case agentFilterChanged(String?)
		case tagTapped(String)
		case tagFilterRemoved(String)
		case showChildRunsTapped(processId: Int)
		case parentFilterCleared
		case filtersCleared
		case sortOrderToggled
		case loadMoreProcessesTapped
		case processesLoaded(Result<HomerProcessPage, any Error>)
		case agentNamesLoaded(Result<[String], any Error>)
		case flowSummariesLoaded([HomerProcess.ID: HomerFlowSummary])
		case processTapped(processId: Int)
		case killTapped(processId: Int)
		case retryTapped(processId: Int)
		case processActionFinished(processId: Int, ProcessAction, Result<Int?, any Error>)
		case alert(PresentationAction<Alert>)

		case questionsLoaded(Result<[HomerQuestion], any Error>)
		case answerDraftChanged(questionId: HomerQuestion.ID, text: String)
		case answerTapped(questionId: HomerQuestion.ID, answer: String)
		case answerFinished(questionId: HomerQuestion.ID, Result<Void, any Error>)
		/// An ask-and-dispatch question's Cancel: asks first, then expires the question so its
		/// agent never starts.
		case cancelQuestionTapped(questionId: HomerQuestion.ID)
		case cancelQuestionConfirmed
		case cancelQuestionDismissed
		case cancelQuestionFinished(questionId: HomerQuestion.ID, Result<Void, any Error>)
		case runQuestionsLoaded(processId: Int, Result<[HomerQuestion], any Error>)

		case healthLoaded(HomerHealth)
		case versionLoaded(String)

		case pendingContinuationCountLoaded(Int)

		/// A page of the web console, e.g. `processes` or `processes/42`.
		case openWebConsoleTapped(path: String, title: String)

		case continuations(HomerContinuationsReducer.Action)
		case agents(HomerAgentsReducer.Action)
		case costs(HomerCostsReducer.Action)
		case processDetail(PresentationAction<HomerProcessDetailReducer.Action>)

		public typealias ProcessAction = HomerProcessAction

		public enum Alert: Equatable, Sendable {
			case killConfirmed(processId: Int)
		}
	}

	private nonisolated enum CancelID: Hashable {
		case sessionCheck
		case processPolling
		case questionPolling
		case flowSummaryPolling
		case continuationCountPolling
		case runQuestionPolling
		case healthPolling
	}

	@Dependency(HomerClient.self)
	private var homerClient

	@Dependency(HomerContinuationsClient.self)
	private var continuationsClient

	@Dependency(\.continuousClock)
	private var clock

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Scope(\.signIn, action: \.signIn) {
			HomerSignInReducer()
		}
		Scope(\.continuations, action: \.continuations) {
			HomerContinuationsReducer()
		}
		Scope(\.agents, action: \.agents) {
			HomerAgentsReducer()
		}
		Scope(\.costs, action: \.costs) {
			HomerCostsReducer()
		}
		Reduce { state, action in
			switch action {
			case .binding(\.rootsOnly):
				// Switching views changes what a row means; a parent filter would override the
				// root view, so going there drops it, as the console does.
				if state.rootsOnly {
					state.parentFilter = nil
				}
				return refilter(&state)

			case .binding:
				return .none

			case .start:
				state.session = .checking
				return .run { [baseURL = state.baseURL] send in
					await send(.sessionChecked(Result { try await homerClient.me(baseURL) }))
				}
				.cancellable(id: CancelID.sessionCheck, cancelInFlight: true)

			case let .sessionChecked(.success(user)):
				state.session = .signedIn(user)
				rememberUsername(user, in: &state)
				return .merge(startPolling(state), syncShownChildPage(&state))

			case let .sessionChecked(.failure(error)):
				state.session = .signedOut
				// No cookie, or one past its 12 h, is the ordinary way to arrive here; anything
				// else (offline, wrong URL) is worth saying on the form.
				if error as? HomerAPIError != .unauthorized {
					state.signIn.loginError = error.localizedDescription
				}
				return .none

			case .activated:
				guard !state.isActive else {
					return .none
				}
				state.isActive = true
				guard state.user != nil else {
					return .none
				}
				return .merge(startPolling(state), syncShownChildPage(&state))

			case .deactivated:
				state.isActive = false
				// Its polls belong to the instance on screen.
				state.processDetail = nil
				return .merge(
					.cancel(id: CancelID.processPolling),
					.cancel(id: CancelID.flowSummaryPolling),
					.cancel(id: CancelID.continuationCountPolling),
					.cancel(id: CancelID.healthPolling),
					syncShownChildPage(&state)
				)

			case let .signIn(.delegate(.signedIn(_, user))), let .signedIn(user):
				// Someone else's data (the add form signed in to this instance as another user)
				// is not this user's to see.
				let cleared = state.user?.username != user.username ? clearData(&state) : nil
				state.session = .signedIn(user)
				rememberUsername(user, in: &state)
				state.signIn.password = ""
				state.signIn.loginError = nil
				state.signIn.sessionExpired = false
				return .merge(startPolling(state), syncShownChildPage(&state, hidingFirst: cleared))

			case .signIn:
				return .none

			case let .pageChanged(page):
				let previousPage = state.page
				state.page = page
				let questions = page == .questions && state.user != nil ? pollQuestions(state) : .none
				let health: Effect<Action> = page == previousPage ? .none : syncHealthPolling(state)
				return .merge(questions, health, syncShownChildPage(&state))

			case .signOutTapped:
				let baseURL = state.baseURL
				state.session = .signedOut
				state.signIn.sessionExpired = false
				return .merge(
					hide(clearData(&state)),
					stopPolling(),
					.run { _ in
						// Signing out locally does not wait on the server: the call also drops
						// the cookies, whatever the server answers.
						try? await homerClient.logout(baseURL)
					}
				)

			case .refreshTapped:
				guard state.user != nil else {
					return .none
				}
				return .merge(
					pollProcesses(state),
					pollQuestions(state),
					pollRunQuestions(state),
					state.isActive ? pollPendingContinuationCount(state) : .none,
					syncHealthPolling(state),
					send(state.shownChildPage.map { [ChildPageEvent(page: $0, kind: .refresh)] } ?? [])
				)

			case let .statusFilterToggled(status):
				if state.statusFilter.contains(status) {
					state.statusFilter.remove(status)
				}
				else {
					state.statusFilter.insert(status)
				}
				return refilter(&state)

			case let .agentFilterChanged(agentName):
				guard agentName != state.agentFilter else {
					return .none
				}
				state.agentFilter = agentName
				return refilter(&state)

			case let .tagTapped(tag):
				guard !state.tagFilter.contains(tag) else {
					return .none
				}
				state.tagFilter.append(tag)
				return refilter(&state)

			case let .tagFilterRemoved(tag):
				state.tagFilter.removeAll { $0 == tag }
				return refilter(&state)

			case let .showChildRunsTapped(processId):
				state.parentFilter = processId
				return refilter(&state)

			case .parentFilterCleared:
				state.parentFilter = nil
				return refilter(&state)

			case .filtersCleared:
				guard state.hasActiveFilters else {
					return .none
				}
				state.statusFilter = []
				state.agentFilter = nil
				state.tagFilter = []
				state.parentFilter = nil
				return refilter(&state)

			case .sortOrderToggled:
				state.oldestFirst.toggle()
				return refilter(&state)

			case .loadMoreProcessesTapped:
				state.processLimit += Self.pageSize
				return pollProcesses(state)

			case let .processesLoaded(.success(page)):
				guard state.user != nil else {
					return .none
				}
				state.processes = IdentifiedArray(page.processes, uniquingIDsWith: { first, _ in first })
				state.processTotal = page.total
				state.hasLoadedProcesses = true
				state.processesError = nil
				return syncFlowSummaries(&state)

			case let .processesLoaded(.failure(error)):
				guard state.user != nil else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.processesError = error.localizedDescription
				return .none

			case let .agentNamesLoaded(.success(names)):
				state.agentNames = names
				return .none

			case .agentNamesLoaded(.failure):
				// The filter just offers no choices; the list itself still loads.
				return .none

			case let .flowSummariesLoaded(summaries):
				let shown = Set(state.flowSummaryRootIDs)
				state.flowSummaries.merge(summaries.filter { shown.contains($0.key) }) { _, new in new }
				return .none

			case let .killTapped(processId):
				state.alert = AlertState {
					TextState("Kill process #\(processId)?")
				} actions: {
					ButtonState(role: .destructive, action: .killConfirmed(processId: processId)) {
						TextState("Kill Process")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState("This cannot be undone.")
				}
				return .none

			case let .alert(.presented(.killConfirmed(processId))):
				guard state.processActionsInFlight.insert(processId).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.processActionFinished(processId: processId, .kill, Result {
						try await homerClient.killProcess(baseURL, processId)
						return nil
					}))
				}

			case .alert:
				return .none

			case let .retryTapped(processId):
				guard state.processActionsInFlight.insert(processId).inserted else {
					return .none
				}
				return .run { [baseURL = state.baseURL] send in
					await send(.processActionFinished(processId: processId, .retry, Result {
						try await homerClient.retryProcess(baseURL, processId)
					}))
				}

			case let .processActionFinished(processId, _, .success(newProcessId)):
				state.processActionsInFlight.remove(processId)
				let refresh = state.isActive ? pollProcesses(state) : .none
				guard let newProcessId else {
					return refresh
				}
				// The console takes you to the new run after a retry.
				return .merge(refresh, .send(.processTapped(processId: newProcessId)))

			case let .processActionFinished(processId, action, .failure(error)):
				state.processActionsInFlight.remove(processId)
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.alert = AlertState {
					TextState(action == .kill ? "Could Not Kill #\(processId)" : "Could Not Retry #\(processId)")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(error.localizedDescription)
				}
				return .none

			case let .processTapped(processId):
				guard let user = state.user else {
					return .none
				}
				state.processDetail = HomerProcessDetailReducer.State(
					baseURL: state.baseURL,
					processId: processId,
					user: user
				)
				return .none

			case .processDetail(.presented(.delegate(.unauthorized))):
				guard state.user != nil else {
					return .none
				}
				return expireSession(&state)

			case .processDetail(.presented(.delegate(.questionsChanged))):
				return state.user != nil ? .merge(pollQuestions(state), pollRunQuestions(state)) : .none

			case .processDetail:
				return .none

			case let .questionsLoaded(.success(questions)):
				guard state.user != nil else {
					return .none
				}
				state.questions = IdentifiedArray(questions, uniquingIDsWith: { first, _ in first })
				state.hasLoadedQuestions = true
				state.questionsError = nil
				// Drafts and errors of questions that closed elsewhere have nothing left to
				// belong to.
				let openIDs = Set(state.questions.ids)
				state.answerDrafts = state.answerDrafts.filter { openIDs.contains($0.key) }
				state.answerErrors = state.answerErrors.filter { openIDs.contains($0.key) }
				return .none

			case let .questionsLoaded(.failure(error)):
				guard state.user != nil else {
					return .none
				}
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.questionsError = error.localizedDescription
				return .none

			case let .answerDraftChanged(questionId, text):
				state.answerDrafts[questionId] = text
				return .none

			case let .answerTapped(questionId, answer):
				let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !answer.isEmpty, !state.answeringQuestionIDs.contains(questionId) else {
					return .none
				}
				state.answeringQuestionIDs.insert(questionId)
				state.answerErrors[questionId] = nil
				return .run { [baseURL = state.baseURL] send in
					await send(.answerFinished(
						questionId: questionId,
						Result { try await homerClient.answerQuestion(baseURL, questionId, answer) }
					))
				}

			case let .answerFinished(questionId, .success):
				state.answeringQuestionIDs.remove(questionId)
				state.questions.remove(id: questionId)
				state.answerDrafts[questionId] = nil
				// The answer resumes the process; its row (and open-question count) moves on.
				return .merge(
					pollQuestions(state),
					pollRunQuestions(state),
					state.isActive ? pollProcesses(state) : .none
				)

			case let .answerFinished(questionId, .failure(error)):
				state.answeringQuestionIDs.remove(questionId)
				if error as? HomerAPIError == .unauthorized {
					return expireSession(&state)
				}
				state.answerErrors[questionId] = error.localizedDescription
				return error as? HomerAPIError == .conflict ? .merge(pollQuestions(state), pollRunQuestions(state)) : .none

			case let .cancelQuestionTapped(questionId):
				state.questionToCancel = questionId
				return .none

			case .cancelQuestionDismissed:
				state.questionToCancel = nil
				return .none

			case .cancelQuestionConfirmed:
				guard let questionId = state.questionToCancel else {
					return .none
				}
				state.questionToCancel = nil
				let question = state.questions[id: questionId] ?? state.runQuestions?.questions[id: questionId]
				guard let dispatchId = question?.dispatch?.id,
				      state.answeringQuestionIDs.insert(questionId).inserted
				else {
					return .none
				}
				state.answerErrors[questionId] = nil
				return .run { [baseURL = state.baseURL] send in
					await send(.cancelQuestionFinished(
						questionId: questionId,
						Result { try await homerClient.cancelDispatch(baseURL, dispatchId) }
					))
				}

			case let .cancelQuestionFinished(questionId, result):
				state.answeringQuestionIDs.remove(questionId)
				switch result {
				case .success:
					state.questions.remove(id: questionId)
					state.answerDrafts[questionId] = nil
				case let .failure(error):
					if error as? HomerAPIError == .unauthorized {
						return expireSession(&state)
					}
					state.answerErrors[questionId] = Self.cancelErrorMessage(error)
				}
				// Either way the lists are re-read, as the console does once the call settles: a
				// refusal means they were stale.
				return .merge(
					pollQuestions(state),
					pollRunQuestions(state),
					state.isActive ? pollProcesses(state) : .none
				)

			case let .runQuestionsLoaded(processId, .success(questions)):
				// An answer for a run no longer on screen, or a user since signed out.
				guard state.user != nil, state.processDetail?.processId == processId else {
					return .none
				}
				state.runQuestions = HomerRunQuestions(
					processId: processId,
					questions: IdentifiedArray(questions, uniquingIDsWith: { first, _ in first })
				)
				return .none

			case let .runQuestionsLoaded(_, .failure(error)):
				guard state.user != nil else {
					return .none
				}
				// The run's page falls back to the run's open questions; the other polls report
				// anything else.
				return error as? HomerAPIError == .unauthorized ? expireSession(&state) : .none

			case let .healthLoaded(health):
				guard state.user != nil else {
					return .none
				}
				state.sweep = health.kubernetesSweep
				return .none

			case let .versionLoaded(version):
				state.homerVersion = version
				return .none

			case let .openWebConsoleTapped(path, title):
				state.webPage = HomerWebPage(
					baseURL: state.baseURL,
					path: path,
					title: title,
					cookies: homerClient.sessionCookies(state.baseURL)
				)
				return .none

			case .continuations(.delegate(let delegate)),
			     .agents(.delegate(let delegate)),
			     .costs(.delegate(let delegate)):
				switch delegate {
				case .unauthorized:
					guard state.user != nil else {
						return .none
					}
					return expireSession(&state)
				case let .openProcess(processId):
					return .send(.processTapped(processId: processId))
				case .continuationsChanged:
					return state.isActive && state.user != nil ? pollPendingContinuationCount(state) : .none
				}

			case let .pendingContinuationCountLoaded(count):
				// A count asked for before signing out lands after the data was dropped.
				guard state.user != nil else {
					return .none
				}
				state.pendingContinuations = count
				return .none

			case .continuations, .agents, .costs:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
		.ifLet(\.$processDetail, action: \.processDetail) {
			HomerProcessDetailReducer()
		}
		// The run on screen changes when its page opens or closes, and when it shows another run
		// (a retry, a sub run, Back): its questions are read again for the new one.
		.onChange(of: \.processDetail?.processId) { _, state in
			state.runQuestions = nil
			return pollRunQuestions(state)
		}
	}

	/// A cancel someone else's answer or cancel beat says so, as the console does.
	static func cancelErrorMessage(_ error: any Error) -> String {
		switch error as? HomerAPIError {
		case .conflict, .server(status: 404, _):
			"This question can no longer be cancelled — it was already answered or cancelled."
		default:
			error.localizedDescription
		}
	}

	// MARK: - Polling

	private func startPolling(_ state: State) -> Effect<Action> {
		.merge(
			pollQuestions(state),
			state.isActive ? pollProcesses(state) : .none,
			state.isActive ? pollPendingContinuationCount(state) : .none,
			state.isActive && state.agentNames.isEmpty ? loadAgentNames(state) : .none,
			state.isActive && state.homerVersion == nil ? loadVersion(state) : .none,
			syncHealthPolling(state)
		)
	}

	private func stopPolling() -> Effect<Action> {
		.merge(
			.cancel(id: CancelID.processPolling),
			.cancel(id: CancelID.questionPolling),
			.cancel(id: CancelID.flowSummaryPolling),
			.cancel(id: CancelID.continuationCountPolling),
			.cancel(id: CancelID.runQuestionPolling),
			.cancel(id: CancelID.healthPolling)
		)
	}

	/// A filter changed: the list restarts from its first page.
	private func refilter(_ state: inout State) -> Effect<Action> {
		state.processLimit = Self.pageSize
		return pollProcesses(state)
	}

	/// Read once: a server's version changes only with a redeploy, which a relaunch picks up. A
	/// failure leaves it unknown — the menu just does not say.
	private func loadVersion(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			if let version = try? await homerClient.version(baseURL) {
				await send(.versionLoaded(version))
			}
		}
	}

	private func loadAgentNames(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			await send(.agentNamesLoaded(Result { try await homerClient.agentNames(baseURL) }))
		}
	}

	/// Keeps the Flow cells' summaries in step with the rows on screen: a new set of top roots
	/// restarts their poll, leaving the root view stops it.
	private func syncFlowSummaries(_ state: inout State) -> Effect<Action> {
		let rootIDs = state.showsFlowColumn
			? Array(state.processes.ids.prefix(Self.flowSummaryRowLimit))
			: []
		guard rootIDs != state.flowSummaryRootIDs else {
			return .none
		}
		state.flowSummaryRootIDs = rootIDs
		let shown = Set(rootIDs)
		state.flowSummaries = state.flowSummaries.filter { shown.contains($0.key) }
		guard !rootIDs.isEmpty else {
			return .cancel(id: CancelID.flowSummaryPolling)
		}
		return .run { [baseURL = state.baseURL] send in
			while true {
				let summaries = await withTaskGroup(of: (Int, HomerFlowSummary?).self) { group in
					for rootID in rootIDs {
						group.addTask {
							let query = HomerProcessQuery(rootProcessId: rootID, limit: HomerFlowSummary.fetchLimit)
							// A cell whose summary fails keeps its last one, or a dash.
							let page = try? await homerClient.processes(baseURL, query)
							return (rootID, page.map(HomerFlowSummary.init(page:)))
						}
					}
					var summaries: [Int: HomerFlowSummary] = [:]
					for await (rootID, summary) in group {
						summaries[rootID] = summary
					}
					return summaries
				}
				await send(.flowSummariesLoaded(summaries))
				try await clock.sleep(for: Self.flowSummaryPollInterval)
			}
		}
		.cancellable(id: CancelID.flowSummaryPolling, cancelInFlight: true)
	}

	/// Fetches right away, then on the console's cadence. Restarting it (a filter change, "Load
	/// more") replaces the running loop, so a slow answer for the old query never lands after
	/// the new one.
	private func pollProcesses(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, query = state.processQuery] send in
			while true {
				await send(.processesLoaded(Result { try await homerClient.processes(baseURL, query) }))
				try await clock.sleep(for: Self.processPollInterval)
			}
		}
		.cancellable(id: CancelID.processPolling, cancelInFlight: true)
	}

	private func pollQuestions(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				await send(.questionsLoaded(Result { try await homerClient.openQuestions(baseURL) }))
				try await clock.sleep(for: Self.questionPollInterval)
			}
		}
		.cancellable(id: CancelID.questionPolling, cancelInFlight: true)
	}

	/// The questions of the run on screen, all of them: its page shows what was answered and what
	/// the answers started. On the console's questions cadence, while the page is up.
	private func pollRunQuestions(_ state: State) -> Effect<Action> {
		guard state.user != nil, let processId = state.processDetail?.processId else {
			return .cancel(id: CancelID.runQuestionPolling)
		}
		return .run { [baseURL = state.baseURL] send in
			while true {
				await send(.runQuestionsLoaded(
					processId: processId,
					Result { try await homerClient.runQuestions(baseURL, processId) }
				))
				try await clock.sleep(for: Self.questionPollInterval)
			}
		}
		.cancellable(id: CancelID.runQuestionPolling, cancelInFlight: true)
	}

	/// `/health` is read only while the process list, which shows its sweep, is on screen. A
	/// failure keeps the last answer: the banner has nowhere to say why.
	private func syncHealthPolling(_ state: State) -> Effect<Action> {
		guard state.user != nil, state.isActive, state.page == .processes else {
			return .cancel(id: CancelID.healthPolling)
		}
		return .run { [baseURL = state.baseURL] send in
			while true {
				if let health = try? await homerClient.health(baseURL) {
					await send(.healthLoaded(health))
				}
				try await clock.sleep(for: Self.healthPollInterval)
			}
		}
		.cancellable(id: CancelID.healthPolling, cancelInFlight: true)
	}

	/// The console's cadence (`usePendingContinuationsCount`): there is no continuation event to
	/// listen to. A failure keeps the last count: the badge has nowhere to say why, and the
	/// other polls report an expired session or an unreachable server.
	private func pollPendingContinuationCount(_ state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL] send in
			while true {
				if let count = try? await continuationsClient.pendingCount(baseURL) {
					await send(.pendingContinuationCountLoaded(count))
				}
				try await clock.sleep(for: HomerContinuationsReducer.pollInterval)
			}
		}
		.cancellable(id: CancelID.continuationCountPolling, cancelInFlight: true)
	}

	/// The form's username for the next sign-in, kept across relaunches.
	private func rememberUsername(_ user: HomerUser, in state: inout State) {
		state.signIn.username = user.username
		@Shared(.homerUsernames) var usernames
		$usernames.withLock { [baseURL = state.baseURL] in $0[baseURL] = user.username }
	}

	/// A call answered 401 on a live session: the cookie expired or the server dropped it.
	/// Back to the sign-in form, which says why.
	private func expireSession(_ state: inout State) -> Effect<Action> {
		state.session = .signedOut
		state.signIn.sessionExpired = true
		return .merge(hide(clearData(&state)), stopPolling())
	}

	// MARK: - Page reducers

	/// Tells the page reducers which of them is on screen: the one the console's page names,
	/// while this instance is on screen and signed in. The admin-only pages stay hidden for
	/// anyone else — the console offers them only to admins. `hidingFirst` is a page whose
	/// state was just replaced and whose poll must stop before anything is shown again.
	private func syncShownChildPage(
		_ state: inout State,
		hidingFirst hiddenPage: HomerChildPage? = nil
	) -> Effect<Action> {
		let page: HomerChildPage? = if let user = state.user, state.isActive,
			!state.page.isAdminOnly || user.isAdmin
		{
			HomerChildPage(state.page)
		}
		else {
			nil
		}
		var events = hiddenPage.map { [ChildPageEvent(page: $0, kind: .hidden)] } ?? []
		if page != state.shownChildPage {
			if let previous = state.shownChildPage {
				events.append(ChildPageEvent(page: previous, kind: .hidden))
			}
			state.shownChildPage = page
			if let page {
				events.append(ChildPageEvent(page: page, kind: .shown))
			}
		}
		return send(events)
	}

	private func hide(_ page: HomerChildPage?) -> Effect<Action> {
		send(page.map { [ChildPageEvent(page: $0, kind: .hidden)] } ?? [])
	}

	private struct ChildPageEvent: Sendable {
		enum Kind: Sendable {
			case shown
			case hidden
			case refresh
		}

		let page: HomerChildPage
		let kind: Kind
	}

	/// In order, from one effect: a page hidden and shown again (another user signed in) must
	/// stop its old poll before it starts the new one.
	private func send(_ events: [ChildPageEvent]) -> Effect<Action> {
		guard !events.isEmpty else {
			return .none
		}
		return .run { send in
			for event in events {
				switch (event.page, event.kind) {
				case (.continuations, .shown):
					await send(.continuations(.shown))
				case (.continuations, .hidden):
					await send(.continuations(.hidden))
				case (.continuations, .refresh):
					await send(.continuations(.refreshTapped))
				case (.agents, .shown):
					await send(.agents(.shown(.agents)))
				case (.schedules, .shown):
					await send(.agents(.shown(.schedules)))
				case (.agents, .hidden), (.schedules, .hidden):
					await send(.agents(.hidden))
				case (.agents, .refresh), (.schedules, .refresh):
					await send(.agents(.refreshTapped))
				case (.costs, .shown):
					await send(.costs(.shown))
				case (.costs, .hidden):
					await send(.costs(.hidden))
				case (.costs, .refresh):
					await send(.costs(.refreshTapped))
				}
			}
		}
	}

	/// Drops everything the signed-in user saw, and returns the page reducer that was on
	/// screen: its poll is still running, and the caller hides it.
	private func clearData(_ state: inout State) -> HomerChildPage? {
		let shownChildPage = state.shownChildPage
		state.shownChildPage = nil
		state.continuations = HomerContinuationsReducer.State(baseURL: state.baseURL)
		state.agents = HomerAgentsReducer.State(baseURL: state.baseURL)
		state.costs = HomerCostsReducer.State(baseURL: state.baseURL)
		state.processes = []
		state.processTotal = 0
		state.processLimit = Self.pageSize
		state.hasLoadedProcesses = false
		state.processesError = nil
		state.flowSummaries = [:]
		state.flowSummaryRootIDs = []
		state.processActionsInFlight = []
		state.agentNames = []
		state.agentFilter = nil
		state.tagFilter = []
		state.parentFilter = nil
		state.alert = nil
		state.questions = []
		state.hasLoadedQuestions = false
		state.questionsError = nil
		state.answerDrafts = [:]
		state.answeringQuestionIDs = []
		state.answerErrors = [:]
		state.questionToCancel = nil
		state.runQuestions = nil
		state.sweep = nil
		state.pendingContinuations = nil
		state.webPage = nil
		state.processDetail = nil
		return shownChildPage
	}
}

/// Every question one run asked, as its page shows them.
public struct HomerRunQuestions: Equatable, Sendable {
	public let processId: Int
	public var questions: IdentifiedArrayOf<HomerQuestion>
}
