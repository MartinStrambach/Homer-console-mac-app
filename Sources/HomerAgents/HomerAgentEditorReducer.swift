import ComposableArchitecture
import Foundation
import HomerCore

/// An agent's editor (the console's `agents/[name]/edit/page.tsx`), shown in place of the page
/// that opened it: the agent directory's files, the open file's text with Save, and the Debug
/// panel. It opens the definition (`agent.yaml`, else `agent.json`) first. A save of the
/// definition is checked against the server's schema, which answers what is wrong; the server
/// then reloads the agent, and the agents list is refetched to show it.
///
/// Unsaved changes are kept until the editor goes: opening another file, or Back, asks first.
@Reducer
public struct HomerAgentEditorReducer: Sendable {
	@ObservableState
	public struct State: Equatable {
		public let baseURL: String
		public let agentName: String
		/// The page it is shown in place of, and goes back to.
		public let openedFrom: HomerAgentsReducer.Page
		/// The list's, kept current by `HomerAgentsReducer`; nil once the list no longer has it.
		public internal(set) var agent: HomerAgent?

		/// Directories first, then by path; nil until first read.
		public internal(set) var files: [HomerAgentFile]?
		public internal(set) var isLoadingFiles = false
		public internal(set) var filesError: String?

		public internal(set) var activePath: String?
		/// The open file's text as edited.
		public var buffer = ""
		/// The open file as last read or saved; nil while it is read.
		public internal(set) var savedContent: String?
		public internal(set) var fileError: String?
		public internal(set) var isSaving = false
		/// Why a save, delete or create failed.
		public internal(set) var saveError: String?
		/// What the server's schema check found wrong with a saved definition.
		public internal(set) var schemaErrors: [String]?

		/// "New File"'s prompt.
		public var isNewFilePromptShown = false
		public var newFileName = ""

		public var debug: HomerAgentDebugReducer.State
		/// "Discard unsaved changes?" and "Delete …?".
		@Presents
		public var alert: AlertState<Action.Alert>?

		public init(
			baseURL: String,
			agentName: String,
			openedFrom: HomerAgentsReducer.Page = .agents,
			agent: HomerAgent? = nil
		) {
			self.baseURL = baseURL
			self.agentName = agentName
			self.openedFrom = openedFrom
			self.agent = agent
			debug = HomerAgentDebugReducer.State(baseURL: baseURL, agentName: agentName, agent: agent)
		}

		/// The text differs from the file on the server.
		public var isDirty: Bool {
			savedContent.map { buffer != $0 } ?? false
		}

		public var isLoadingFile: Bool {
			activePath != nil && savedContent == nil && fileError == nil
		}

		public var canSave: Bool {
			activePath != nil && isDirty && !isSaving
		}

		mutating func update(agent: HomerAgent?) {
			self.agent = agent
			if let agent {
				debug.update(from: agent)
			}
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		/// Reads the file list; the parent sends it when it opens the editor.
		case start
		/// The header's Refresh: the file list, and the open file unless it has changes.
		case refreshTapped
		case filesLoaded(Result<[HomerAgentFile], any Error>)
		case fileTapped(path: String)
		case fileLoaded(path: String, Result<String, any Error>)
		case saveTapped
		case saveFinished(path: String, content: String, Result<Void, any Error>)
		case deleteTapped(path: String)
		case deleteFinished(path: String, Result<Void, any Error>)
		case newFileTapped
		case newFileConfirmed
		case fileCreated(path: String, Result<Void, any Error>)
		case saveErrorDismissed
		case schemaErrorsDismissed
		case backTapped
		case alert(PresentationAction<Alert>)
		case debug(HomerAgentDebugReducer.Action)
		case delegate(Delegate)

		public enum Alert: Equatable, Sendable {
			case discardConfirmed(Discard)
			case deleteConfirmed(path: String)
		}

		/// What unsaved changes are discarded for.
		public enum Discard: Equatable, Sendable {
			case open(path: String)
			case back
		}

		public enum Delegate: Equatable, Sendable {
			/// Back to the page that opened it.
			case back
			/// A file was saved, created or deleted: the server reloaded the agent.
			case filesChanged
			case openProcess(processId: Int)
			case unauthorized
		}
	}

	nonisolated enum CancelID: Hashable {
		case files
		case file
		case fileOperation
	}

	/// Stops whatever the editor still runs. The parent holds it as plain optional state, whose
	/// effects nothing cancels when it goes — and an instance that signs out replaces the
	/// parent's state outright — so the parent sends this when it drops the editor.
	static func cancelEffects<A>() -> Effect<A> {
		.merge(
			.cancel(id: CancelID.files),
			.cancel(id: CancelID.file),
			.cancel(id: CancelID.fileOperation),
			HomerAgentDebugReducer.cancelEffects()
		)
	}

	@Dependency(HomerAgentEditorClient.self)
	private var editorClient

	public init() {}

	public var body: some Reducer<State, Action> {
		BindingReducer()
		Scope(\.debug, action: \.debug) {
			HomerAgentDebugReducer()
		}
		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .start:
				return loadFiles(&state)

			case .refreshTapped:
				guard let path = state.activePath, !state.isDirty, !state.isLoadingFile else {
					return loadFiles(&state)
				}
				return .merge(loadFiles(&state), loadFile(path, state: state))

			case let .filesLoaded(.success(files)):
				state.isLoadingFiles = false
				state.filesError = nil
				state.files = HomerAgentFile.sorted(files)
				guard state.activePath == nil,
				      let definition = HomerAgentFile.definitionPaths.first(where: { path in
				      	files.contains { $0.path == path && !$0.isDirectory }
				      })
				else {
					return .none
				}
				return open(definition, state: &state)

			case let .filesLoaded(.failure(error)):
				state.isLoadingFiles = false
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.filesError = error.localizedDescription
				return .none

			case let .fileTapped(path):
				guard path != state.activePath else {
					return .none
				}
				guard !state.isDirty else {
					state.alert = discardAlert(for: .open(path: path), state: state)
					return .none
				}
				return open(path, state: &state)

			case let .fileLoaded(path, .success(content)):
				// An answer for a file no longer open, or one that would overwrite new changes.
				guard path == state.activePath, !state.isDirty else {
					return .none
				}
				state.buffer = content
				state.savedContent = content
				state.fileError = nil
				return .none

			case let .fileLoaded(path, .failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				guard path == state.activePath, state.savedContent == nil else {
					return .none
				}
				state.fileError = error.localizedDescription
				return .none

			case .saveTapped:
				guard state.canSave, let path = state.activePath else {
					return .none
				}
				state.isSaving = true
				state.saveError = nil
				state.schemaErrors = nil
				return .run { [baseURL = state.baseURL, agentName = state.agentName, content = state.buffer] send in
					await send(.saveFinished(path: path, content: content, Result {
						try await editorClient.saveFile(baseURL, agentName, path, content)
					}))
				}
				.cancellable(id: CancelID.fileOperation)

			case let .saveFinished(path, content, .success):
				state.isSaving = false
				if path == state.activePath {
					state.savedContent = content
				}
				return .merge(loadFiles(&state), .send(.delegate(.filesChanged)))

			case let .saveFinished(_, _, .failure(error)):
				state.isSaving = false
				switch error as? HomerAPIError {
				case .unauthorized:
					return .send(.delegate(.unauthorized))
				case let .invalid(message, errors):
					state.schemaErrors = errors.isEmpty ? [message ?? "Schema validation failed"] : errors
				default:
					state.saveError = error.localizedDescription
				}
				return .none

			case let .deleteTapped(path):
				state.alert = AlertState {
					TextState("Delete \(path)?")
				} actions: {
					ButtonState(role: .destructive, action: .deleteConfirmed(path: path)) {
						TextState("Delete")
					}
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
				} message: {
					TextState("This cannot be undone.")
				}
				return .none

			case let .deleteFinished(path, .success):
				if path == state.activePath {
					state.activePath = nil
					state.buffer = ""
					state.savedContent = nil
					state.fileError = nil
				}
				return .merge(loadFiles(&state), .send(.delegate(.filesChanged)))

			case let .deleteFinished(_, .failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.saveError = error.localizedDescription
				return .none

			case .newFileTapped:
				state.newFileName = ""
				state.isNewFilePromptShown = true
				return .none

			case .newFileConfirmed:
				let path = state.newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
				state.isNewFilePromptShown = false
				state.newFileName = ""
				guard !path.isEmpty else {
					return .none
				}
				state.saveError = nil
				return .run { [baseURL = state.baseURL, agentName = state.agentName] send in
					await send(.fileCreated(path: path, Result {
						try await editorClient.saveFile(baseURL, agentName, path, "")
					}))
				}
				.cancellable(id: CancelID.fileOperation)

			case let .fileCreated(path, .success):
				// Opened as any file is: unsaved changes elsewhere are asked about first.
				return .merge(
					loadFiles(&state),
					.send(.delegate(.filesChanged)),
					.send(.fileTapped(path: path))
				)

			case let .fileCreated(_, .failure(error)):
				if error as? HomerAPIError == .unauthorized {
					return .send(.delegate(.unauthorized))
				}
				state.saveError = error.localizedDescription
				return .none

			case .saveErrorDismissed:
				state.saveError = nil
				return .none

			case .schemaErrorsDismissed:
				state.schemaErrors = nil
				return .none

			case .backTapped:
				guard !state.isDirty else {
					state.alert = discardAlert(for: .back, state: state)
					return .none
				}
				return .send(.delegate(.back))

			case let .alert(.presented(.discardConfirmed(.open(path)))):
				return open(path, state: &state)

			case .alert(.presented(.discardConfirmed(.back))):
				return .send(.delegate(.back))

			case let .alert(.presented(.deleteConfirmed(path))):
				state.saveError = nil
				return .run { [baseURL = state.baseURL, agentName = state.agentName] send in
					await send(.deleteFinished(path: path, Result {
						try await editorClient.deleteFile(baseURL, agentName, path)
					}))
				}
				.cancellable(id: CancelID.fileOperation)

			case .alert:
				return .none

			case let .debug(.delegate(.openProcess(processId))):
				return .send(.delegate(.openProcess(processId: processId)))

			case .debug(.delegate(.unauthorized)):
				return .send(.delegate(.unauthorized))

			case .debug:
				return .none

			case .delegate:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}

	private func discardAlert(for discard: Action.Discard, state: State) -> AlertState<Action.Alert> {
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
			TextState("Your changes to \(state.activePath ?? "the file") will be lost.")
		}
	}

	/// Shows the file and reads it, dropping whatever the last one had.
	private func open(_ path: String, state: inout State) -> Effect<Action> {
		state.activePath = path
		state.buffer = ""
		state.savedContent = nil
		state.fileError = nil
		state.saveError = nil
		state.schemaErrors = nil
		return loadFile(path, state: state)
	}

	private func loadFile(_ path: String, state: State) -> Effect<Action> {
		.run { [baseURL = state.baseURL, agentName = state.agentName] send in
			await send(.fileLoaded(path: path, Result { try await editorClient.file(baseURL, agentName, path) }))
		}
		.cancellable(id: CancelID.file, cancelInFlight: true)
	}

	private func loadFiles(_ state: inout State) -> Effect<Action> {
		state.isLoadingFiles = true
		return .run { [baseURL = state.baseURL, agentName = state.agentName] send in
			await send(.filesLoaded(Result { try await editorClient.files(baseURL, agentName) }))
		}
		.cancellable(id: CancelID.files, cancelInFlight: true)
	}
}
