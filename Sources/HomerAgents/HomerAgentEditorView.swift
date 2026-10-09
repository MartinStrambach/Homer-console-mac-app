import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// An agent's editor (the console's `agents/[name]/edit/page.tsx`), in place of the page that
/// opened it: Back, "Editing name" and Save over the files, the open file and — for a user with
/// a `debug` grant — the Debug panel, side by side at the console's widths.
struct HomerAgentEditorView: View {
	@Bindable
	var store: StoreOf<HomerAgentEditorReducer>
	let user: HomerUser
	/// What Back returns to: the agent's page, or the Agents or Schedules page.
	let backTitle: String

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			if let agent = store.agent {
				if !agent.isWritable {
					notice(
						"Read-Only Agent",
						systemImage: "lock",
						"\(agent.name)'s directory is read-only on the server. Editing is disabled."
					)
				}
				else if !user.isGranted("edit", on: agent.name) {
					notice("No Permission", systemImage: "hand.raised", "You don't have permission to edit this agent.")
				}
				else {
					banners
					panes(agent)
				}
			}
			else {
				notice("Agent Not Found", systemImage: "questionmark.square.dashed", "No agent named \(store.agentName). A reload may have removed it.")
			}
		}
		.alert($store.scope(\.$alert, action: \.alert))
		.alert("New File", isPresented: $store.isNewFilePromptShown) {
			TextField("Path", text: $store.newFileName)
			Button("Create") { store.send(.newFileConfirmed) }
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("New file name (relative to the agent directory):")
		}
		.sheet(item: $store.scope(\.debug.$runSheet, action: \.debug.runSheet)) { runStore in
			HomerAgentDebugRunView(store: runStore)
		}
	}

	// MARK: - Header

	private var header: some View {
		HStack(spacing: 10) {
			Button {
				store.send(.backTapped)
			} label: {
				Label(backTitle, systemImage: "chevron.left")
			}
			.buttonStyle(.scaledBordered)
			.keyboardShortcut("[", modifiers: .command)
			.help("Back to \(backTitle) (⌘[)")

			HStack(spacing: 5) {
				Text("Editing")
				Text(store.agentName)
					.scaledFont(.title3, design: .monospaced)
			}
			.scaledFont(.title3)
			.fontWeight(.semibold)
			.lineLimit(1)
			.truncationMode(.middle)

			if store.isDirty {
				Text("● Unsaved")
					.scaledFont(.caption)
					.foregroundStyle(.orange)
			}

			Spacer()

			if let url = HomerEndpoint.pageURL(
				baseURL: store.baseURL,
				path: HomerAgent(name: store.agentName).consolePath + "/edit"
			) {
				Button {
					NSWorkspace.shared.open(url)
				} label: {
					Label("Open in Browser", systemImage: "safari")
				}
				.buttonStyle(.scaledBordered)
				.help("Open the editor in the web console")
			}

			if store.isSaving {
				ProgressView()
					.controlSize(.small)
			}
			Button {
				store.send(.saveTapped)
			} label: {
				Label(store.isSaving ? "Saving…" : "Save", systemImage: "square.and.arrow.down")
			}
			.buttonStyle(.scaledBorderedProminent)
			.keyboardShortcut("s", modifiers: .command)
			.disabled(!store.canSave)
			.help("Save \(store.activePath ?? "the file") (⌘S)")
		}
		.scaledFont(.callout)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	@ViewBuilder
	private var banners: some View {
		if let error = store.saveError {
			HomerAgentDismissableBanner(onDismiss: { store.send(.saveErrorDismissed) }) {
				Label(error, systemImage: "exclamationmark.triangle.fill")
					.foregroundStyle(.red)
					.textSelection(.enabled)
			}
			.background(Color.red.opacity(0.08))
			Divider()
		}
		if let errors = store.schemaErrors {
			HomerAgentDismissableBanner(onDismiss: { store.send(.schemaErrorsDismissed) }) {
				VStack(alignment: .leading, spacing: 3) {
					Text("Schema validation failed:")
						.fontWeight(.medium)
					ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
						Text("•  \(error)")
							.textSelection(.enabled)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.foregroundStyle(.red)
			}
			.background(Color.red.opacity(0.08))
			Divider()
		}
	}

	private func notice(_ title: String, systemImage: String, _ description: String) -> some View {
		ContentUnavailableView {
			Label(title, systemImage: systemImage)
		} description: {
			Text(description)
		} actions: {
			Button(backTitle) { store.send(.backTapped) }
				.buttonStyle(.scaledBordered)
		}
	}

	// MARK: - Panes

	private func panes(_ agent: HomerAgent) -> some View {
		HStack(spacing: 0) {
			HomerAgentFileTree(store: store)
				.frame(width: 256)
				.background(Color.secondary.opacity(0.05))
			Divider()
			editor
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			if user.canDebug(agent) {
				Divider()
				HomerAgentDebugPanel(store: store.scope(\.debug, action: \.debug))
					.frame(width: 320)
					.background(Color.secondary.opacity(0.05))
			}
		}
		.frame(maxHeight: .infinity)
	}

	@ViewBuilder
	private var editor: some View {
		if let path = store.activePath {
			VStack(spacing: 0) {
				Text(path)
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 10)
					.padding(.vertical, 4)
					.background(Color.secondary.opacity(0.04))
				Divider()
				if let error = store.fileError {
					ContentUnavailableView {
						Label("Could Not Open \(path)", systemImage: "exclamationmark.triangle")
					} description: {
						Text(error)
					}
				}
				else if store.isLoadingFile {
					ProgressView("Loading \(path)…")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
				else {
					HomerCodeEditor(
						text: $store.buffer,
						language: HomerAgentFileLanguage(path: path),
						isEditable: !store.isSaving,
						documentID: path
					)
				}
			}
		}
		else {
			Text("Select a file to edit")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}

/// The agent directory's files (`file-tree.tsx`): directories first, the open file selected, a
/// file's trash button on hover — never the definition's — and "New File" in the header.
private struct HomerAgentFileTree: View {
	let store: StoreOf<HomerAgentEditorReducer>

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text("FILES")
					.scaledFont(.caption)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.tracking(0.8)
				if store.isLoadingFiles, store.files != nil {
					ProgressView()
						.controlSize(.mini)
				}
				Spacer()
				Button {
					store.send(.newFileTapped)
				} label: {
					Image(systemName: "plus")
				}
				.buttonStyle(.borderless)
				.help("New file")
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			Divider()

			if let error = store.filesError {
				Text(error)
					.scaledFont(.caption)
					.foregroundStyle(.red)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(10)
			}
			if let files = store.files {
				if files.isEmpty {
					placeholder("No files")
				}
				else {
					List(selection: Binding(
						get: { store.activePath },
						set: { path in
							if let path {
								store.send(.fileTapped(path: path))
							}
						}
					)) {
						ForEach(files) { file in
							HomerAgentFileRow(file: file, store: store)
								.tag(file.path)
								.selectionDisabled(file.isDirectory)
						}
					}
					.listStyle(.sidebar)
					.scrollContentBackground(.hidden)
				}
			}
			else if store.filesError == nil {
				placeholder("Loading files…")
			}
		}
	}

	private func placeholder(_ text: String) -> some View {
		Text(text)
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.padding(10)
	}
}

private struct HomerAgentFileRow: View {
	let file: HomerAgentFile
	let store: StoreOf<HomerAgentEditorReducer>

	@State
	private var isHovered = false

	private var canDelete: Bool {
		!file.isDirectory && !file.isDefinition
	}

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: file.isDirectory ? "folder" : "doc.text")
				.foregroundStyle(.secondary)
			Text(file.path)
				.scaledFont(.callout, design: .monospaced)
				.lineLimit(1)
				.truncationMode(.middle)
				.foregroundStyle(file.isDirectory ? .secondary : .primary)
			Spacer(minLength: 0)
			if canDelete {
				Button {
					store.send(.deleteTapped(path: file.path))
				} label: {
					Image(systemName: "trash")
				}
				.buttonStyle(.borderless)
				.opacity(isHovered ? 1 : 0)
				.help("Delete \(file.path)")
			}
		}
		.help(file.path)
		.onHover { isHovered = $0 }
		.contextMenu {
			if !file.isDirectory {
				Button {
					store.send(.fileTapped(path: file.path))
				} label: {
					Label("Open", systemImage: "doc.text")
				}
			}
			Button {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(file.path, forType: .string)
			} label: {
				Label("Copy Path", systemImage: "doc.on.doc")
			}
			if canDelete {
				Divider()
				Button(role: .destructive) {
					store.send(.deleteTapped(path: file.path))
				} label: {
					Label("Delete…", systemImage: "trash")
				}
			}
		}
	}
}
