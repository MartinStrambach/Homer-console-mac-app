import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerAgents
@testable import HomerCore
import Testing

@MainActor
@Suite("Homer agent editor", .dependencies)
struct HomerAgentEditorReducerTests {
	private nonisolated static let baseURL = "https://homer.example.com"
	private let factory = HomerAgent(
		name: "factory",
		inputs: [HomerAgent.Input(paramName: "ticket", envName: "TICKET")],
		scriptCount: 2
	)
	private let definition = "name: factory\ncommands:\n  - echo hi\n"

	private func agentsState(shownPage: HomerAgentsReducer.Page? = .agents) -> HomerAgentsReducer.State {
		var state = HomerAgentsReducer.State(baseURL: Self.baseURL)
		state.agents = [factory]
		state.hasLoaded = true
		state.shownPage = shownPage
		return state
	}

	/// An editor with `agent.yaml` read and open.
	private func editorState() -> HomerAgentEditorReducer.State {
		var state = HomerAgentEditorReducer.State(baseURL: Self.baseURL, agentName: "factory", agent: factory)
		state.files = [HomerAgentFile(path: "agent.yaml"), HomerAgentFile(path: "run.sh")]
		state.activePath = "agent.yaml"
		state.buffer = definition
		state.savedContent = definition
		return state
	}

	private func discardAlert(
		_ discard: HomerAgentEditorReducer.Action.Discard,
		path: String = "agent.yaml"
	) -> AlertState<HomerAgentEditorReducer.Action.Alert> {
		AlertState {
			TextState("Discard unsaved changes?")
		} actions: {
			ButtonState(role: .destructive, action: .discardConfirmed(discard)) {
				TextState("Discard Changes")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("Your changes to \(path) will be lost.")
		}
	}

	// MARK: - Opening

	@Test("Edit opens the editor in place of the cards, reads the files and opens the definition")
	func opensDefinition() async {
		let reads = LockIsolated<[String]>([])
		let store = TestStore(initialState: agentsState()) {
			HomerAgentsReducer()
		} withDependencies: { [definition] in
			$0[HomerAgentEditorClient.self].files = { baseURL, agentName in
				#expect(baseURL == Self.baseURL)
				#expect(agentName == "factory")
				return [
					HomerAgentFile(path: "run.sh", size: 10),
					HomerAgentFile(path: "agent.yaml", size: 30),
					HomerAgentFile(path: "prompts", isDirectory: true),
					HomerAgentFile(path: "README.md"),
				]
			}
			$0[HomerAgentEditorClient.self].file = { _, _, path in
				reads.withValue { $0.append(path) }
				return definition
			}
		}

		await store.send(.editTapped(agentName: "factory")) {
			$0.editor = HomerAgentEditorReducer.State(
				baseURL: Self.baseURL,
				agentName: "factory",
				openedFrom: .agents,
				agent: factory
			)
		}
		await store.receive(\.editor.start) {
			$0.editor?.isLoadingFiles = true
		}
		await store.receive(\.editor.filesLoaded) {
			$0.editor?.isLoadingFiles = false
			$0.editor?.files = [
				HomerAgentFile(path: "prompts", isDirectory: true),
				HomerAgentFile(path: "agent.yaml", size: 30),
				HomerAgentFile(path: "README.md"),
				HomerAgentFile(path: "run.sh", size: 10),
			]
			$0.editor?.activePath = "agent.yaml"
		}
		#expect(store.state.editor?.isLoadingFile == true)
		await store.receive(\.editor.fileLoaded) {
			$0.editor?.buffer = definition
			$0.editor?.savedContent = definition
		}
		#expect(reads.value == ["agent.yaml"])
		#expect(store.state.editor?.isDirty == false)
		#expect(store.state.editorBackTitle == "Agents")
	}

	@Test("editing over the agent's page stops its poll until the editor goes")
	func coversAgentPage() async {
		let clock = TestClock()
		let polls = LockIsolated(0)
		var initialState = agentsState()
		initialState.detail = HomerAgentDetailReducer.State(baseURL: Self.baseURL, agentName: "factory", agent: factory)
		initialState.detail?.isShown = true
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		} withDependencies: { [factory] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].agents = { _ in [factory] }
			$0[HomerAgentEditorClient.self].files = { _, _ in [] }
			$0[HomerClient.self].processes = { _, _ in
				polls.withValue { $0 += 1 }
				return HomerProcessPage(processes: [], total: 0)
			}
		}

		await store.send(.detail(.editTapped))
		await store.receive(\.detail.delegate, .edit)
		await store.receive(\.editTapped) {
			$0.editor = HomerAgentEditorReducer.State(
				baseURL: Self.baseURL,
				agentName: "factory",
				openedFrom: .agents,
				agent: factory
			)
			$0.detail?.isShown = false
		}
		await store.receive(\.editor.start) {
			$0.editor?.isLoadingFiles = true
		}
		await store.receive(\.editor.filesLoaded) {
			$0.editor?.isLoadingFiles = false
			$0.editor?.files = []
		}

		// Hidden and shown again, the page under the editor stays stopped.
		await store.send(.hidden) {
			$0.shownPage = nil
		}
		await store.send(.shown(.agents)) {
			$0.shownPage = .agents
		}
		await store.receive(\.agentsLoaded)
		#expect(polls.value == 0)

		await store.send(.editor(.backTapped))
		await store.receive(\.editor.delegate, .back) {
			$0.editor = nil
		}
		await store.receive(\.detail.shown) {
			$0.detail?.isShown = true
		}
		await store.receive(\.detail.runsLoaded) {
			$0.detail?.hasLoadedRuns = true
		}
		#expect(polls.value == 1)
		await store.send(.hidden) {
			$0.shownPage = nil
			$0.detail?.isShown = false
		}
	}

	// MARK: - Saving

	@Test("Save writes the text, refetches the files and tells the list the agent changed")
	func save() async {
		let saved = LockIsolated<[String]>([])
		let edited = definition + "description: Builds things\n"
		var initialState = editorState()
		initialState.buffer = edited
		let store = TestStore(initialState: initialState) {
			HomerAgentEditorReducer()
		} withDependencies: {
			$0[HomerAgentEditorClient.self].saveFile = { _, agentName, path, content in
				#expect(agentName == "factory")
				saved.withValue { $0.append("\(path)=\(content)") }
			}
			$0[HomerAgentEditorClient.self].files = { _, _ in
				[HomerAgentFile(path: "agent.yaml", size: 60), HomerAgentFile(path: "run.sh")]
			}
		}
		#expect(store.state.isDirty)

		await store.send(.saveTapped) {
			$0.isSaving = true
		}
		await store.receive(\.saveFinished) {
			$0.isSaving = false
			$0.savedContent = edited
			$0.isLoadingFiles = true
		}
		await store.receive(\.delegate, .filesChanged)
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [HomerAgentFile(path: "agent.yaml", size: 60), HomerAgentFile(path: "run.sh")]
		}
		#expect(saved.value == ["agent.yaml=\(edited)"])
		#expect(!store.state.isDirty)

		// Nothing left to save.
		await store.send(.saveTapped)
	}

	@Test("a definition the schema refuses lists the server's reasons and stays unsaved")
	func schemaErrors() async {
		var initialState = editorState()
		initialState.buffer = "name: [\n"
		let store = TestStore(initialState: initialState) {
			HomerAgentEditorReducer()
		} withDependencies: {
			$0[HomerAgentEditorClient.self].saveFile = { _, _, _, _ in
				throw HomerAPIError.invalid(
					message: "Agent definition invalid",
					errors: ["$.commands: is missing", "$.name: must be a string"]
				)
			}
		}

		await store.send(.saveTapped) {
			$0.isSaving = true
		}
		await store.receive(\.saveFinished) {
			$0.isSaving = false
			$0.schemaErrors = ["$.commands: is missing", "$.name: must be a string"]
		}
		#expect(store.state.isDirty)
		await store.send(.schemaErrorsDismissed) {
			$0.schemaErrors = nil
		}

		store.dependencies[HomerAgentEditorClient.self].saveFile = { _, _, _, _ in
			throw HomerAPIError.server(status: 409, message: "Agent 'other' already exists")
		}
		await store.send(.saveTapped) {
			$0.isSaving = true
		}
		await store.receive(\.saveFinished) {
			$0.isSaving = false
			$0.saveError = "Agent 'other' already exists"
		}
	}

	// MARK: - Unsaved changes

	@Test("another file, or Back, with unsaved changes asks first")
	func asksBeforeDiscarding() async {
		var initialState = editorState()
		initialState.buffer = definition + "# edited\n"
		let store = TestStore(initialState: initialState) {
			HomerAgentEditorReducer()
		} withDependencies: {
			$0[HomerAgentEditorClient.self].file = { _, _, path in
				#expect(path == "run.sh")
				return "#!/bin/sh\n"
			}
		}

		await store.send(.fileTapped(path: "run.sh")) {
			$0.alert = discardAlert(.open(path: "run.sh"))
		}
		await store.send(.alert(.dismiss)) {
			$0.alert = nil
		}
		await store.send(.backTapped) {
			$0.alert = discardAlert(.back)
		}
		await store.send(.alert(.dismiss)) {
			$0.alert = nil
		}

		await store.send(.fileTapped(path: "run.sh")) {
			$0.alert = discardAlert(.open(path: "run.sh"))
		}
		await store.send(.alert(.presented(.discardConfirmed(.open(path: "run.sh"))))) {
			$0.alert = nil
			$0.activePath = "run.sh"
			$0.buffer = ""
			$0.savedContent = nil
		}
		await store.receive(\.fileLoaded) {
			$0.buffer = "#!/bin/sh\n"
			$0.savedContent = "#!/bin/sh\n"
		}

		// Nothing to lose: Back goes straight back.
		await store.send(.backTapped)
		await store.receive(\.delegate, .back)
	}

	@Test("a refresh reads the open file again only when it has no changes")
	func refreshKeepsChanges() async {
		let reads = LockIsolated(0)
		var initialState = editorState()
		initialState.buffer = definition + "# edited\n"
		let store = TestStore(initialState: initialState) {
			HomerAgentEditorReducer()
		} withDependencies: { [definition] in
			$0[HomerAgentEditorClient.self].files = { _, _ in [HomerAgentFile(path: "agent.yaml"), HomerAgentFile(path: "run.sh")] }
			$0[HomerAgentEditorClient.self].file = { _, _, _ in
				reads.withValue { $0 += 1 }
				return definition + "# from elsewhere\n"
			}
		}

		await store.send(.refreshTapped) {
			$0.isLoadingFiles = true
		}
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
		}
		#expect(reads.value == 0)

		await store.send(.binding(.set(\.buffer, definition))) {
			$0.buffer = definition
		}
		await store.send(.refreshTapped) {
			$0.isLoadingFiles = true
		}
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
		}
		await store.receive(\.fileLoaded) {
			$0.buffer = definition + "# from elsewhere\n"
			$0.savedContent = definition + "# from elsewhere\n"
		}
	}

	// MARK: - Files

	@Test("Delete asks, removes the file, and closes it when it is the open one")
	func delete() async {
		let deleted = LockIsolated<[String]>([])
		var initialState = editorState()
		initialState.activePath = "run.sh"
		let store = TestStore(initialState: initialState) {
			HomerAgentEditorReducer()
		} withDependencies: { [definition] in
			$0[HomerAgentEditorClient.self].deleteFile = { _, _, path in
				deleted.withValue { $0.append(path) }
			}
			$0[HomerAgentEditorClient.self].files = { _, _ in [HomerAgentFile(path: "agent.yaml")] }
			$0[HomerAgentEditorClient.self].file = { _, _, _ in definition }
		}

		await store.send(.deleteTapped(path: "run.sh")) {
			$0.alert = AlertState {
				TextState("Delete run.sh?")
			} actions: {
				ButtonState(role: .destructive, action: .deleteConfirmed(path: "run.sh")) {
					TextState("Delete")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState("This cannot be undone.")
			}
		}
		await store.send(.alert(.presented(.deleteConfirmed(path: "run.sh")))) {
			$0.alert = nil
		}
		await store.receive(\.deleteFinished) {
			$0.activePath = nil
			$0.buffer = ""
			$0.savedContent = nil
			$0.isLoadingFiles = true
		}
		await store.receive(\.delegate, .filesChanged)
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [HomerAgentFile(path: "agent.yaml")]
			$0.activePath = "agent.yaml"
		}
		await store.receive(\.fileLoaded) {
			$0.buffer = definition
			$0.savedContent = definition
		}
		#expect(deleted.value == ["run.sh"])
	}

	@Test("New File creates the file empty and opens it")
	func newFile() async {
		let saved = LockIsolated<[String]>([])
		let store = TestStore(initialState: editorState()) {
			HomerAgentEditorReducer()
		} withDependencies: {
			$0[HomerAgentEditorClient.self].saveFile = { _, _, path, content in
				saved.withValue { $0.append("\(path)=\(content)") }
			}
			$0[HomerAgentEditorClient.self].files = { _, _ in
				[HomerAgentFile(path: "agent.yaml"), HomerAgentFile(path: "prompts/review.md"), HomerAgentFile(path: "run.sh")]
			}
			$0[HomerAgentEditorClient.self].file = { _, _, _ in "" }
		}

		await store.send(.newFileTapped) {
			$0.isNewFilePromptShown = true
		}
		await store.send(.binding(.set(\.newFileName, "  prompts/review.md "))) {
			$0.newFileName = "  prompts/review.md "
		}
		await store.send(.newFileConfirmed) {
			$0.isNewFilePromptShown = false
			$0.newFileName = ""
		}
		await store.receive(\.fileCreated) {
			$0.isLoadingFiles = true
		}
		await store.receive(\.delegate, .filesChanged)
		await store.receive(\.fileTapped) {
			$0.activePath = "prompts/review.md"
			$0.buffer = ""
			$0.savedContent = nil
		}
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
			$0.files = [HomerAgentFile(path: "agent.yaml"), HomerAgentFile(path: "prompts/review.md"), HomerAgentFile(path: "run.sh")]
		}
		await store.receive(\.fileLoaded) {
			$0.savedContent = ""
		}
		#expect(saved.value == ["prompts/review.md="])
	}

	@Test("a 401 asks the instance to sign out")
	func unauthorized() async {
		let store = TestStore(initialState: HomerAgentEditorReducer.State(baseURL: Self.baseURL, agentName: "factory")) {
			HomerAgentEditorReducer()
		} withDependencies: {
			$0[HomerAgentEditorClient.self].files = { _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.start) {
			$0.isLoadingFiles = true
		}
		await store.receive(\.filesLoaded) {
			$0.isLoadingFiles = false
		}
		await store.receive(\.delegate, .unauthorized)
	}
}
