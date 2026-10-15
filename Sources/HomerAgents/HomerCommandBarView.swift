import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The command bar's popover: the field, where the text goes, and the commands to pick from.
/// Return runs, Tab completes the command being typed, Esc closes the popover.
public struct HomerCommandBarView: View {
	@Bindable
	var store: StoreOf<HomerCommandBarReducer>

	@FocusState
	private var isFieldFocused: Bool

	public init(store: StoreOf<HomerCommandBarReducer>) {
		self.store = store
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			field
			routeLine
			if let error = store.runError {
				Label(error, systemImage: "exclamationmark.triangle.fill")
					.scaledFont(.callout)
					.foregroundStyle(.red)
					.fixedSize(horizontal: false, vertical: true)
			}
			Divider()
			content
		}
		.padding(12)
		.frame(width: 480)
		.task {
			isFieldFocused = true
			store.send(.appeared)
		}
	}

	private var field: some View {
		HStack(spacing: 8) {
			Image(systemName: "command")
				.foregroundStyle(.secondary)
			TextField("A command and its text, e.g. check MOB-1234", text: $store.text)
				.textFieldStyle(.plain)
				.scaledFont(size: 15)
				.focused($isFieldFocused)
				.onSubmit { store.send(.runTapped) }
				.onKeyPress(.tab) {
					store.send(.completeTapped)
					return .handled
				}
				.disabled(store.isRunning)
			if store.isRunning {
				ProgressView()
					.controlSize(.small)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 7)
		.background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
	}

	/// What Return does with the text.
	@ViewBuilder
	private var routeLine: some View {
		switch store.route {
		case let .command(command, prompt):
			HStack(spacing: 4) {
				Image(systemName: "return")
				Text("Runs **\(command.agent)**")
				if prompt.isEmpty {
					Text("with no \(command.promptParam)")
				}
				else {
					Text("with \(command.promptParam) = \(prompt)")
						.lineLimit(1)
						.truncationMode(.tail)
				}
			}
			.scaledFont(.callout)
			.foregroundStyle(.secondary)
		case .help:
			Text("The commands:")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
		case let .unknown(word):
			Text("No command \"\(word)\", and no default one")
				.scaledFont(.callout)
				.foregroundStyle(.orange)
		case nil:
			EmptyView()
		}
	}

	@ViewBuilder
	private var content: some View {
		switch store.commands {
		case .loading:
			HStack {
				Spacer()
				ProgressView()
					.controlSize(.small)
				Spacer()
			}
			.padding(.vertical, 8)
		case .unsupported:
			message("This Homer does not list Slack commands — that needs a newer Homer.")
		case let .failed(error):
			message("The commands could not be read: \(error)")
		case let .loaded(list):
			if list.commands.isEmpty {
				message("No commands: this Homer has no Slack connector set up, or none of its commands runs an agent you may run.")
			}
			else {
				suggestions(intro: store.route == .help ? list.intro : nil)
			}
		}
	}

	private func message(_ text: String) -> some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
	}

	private func suggestions(intro: String?) -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 2) {
				if let intro {
					Text(intro)
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom, 6)
				}
				ForEach(store.suggestions) { command in
					Button {
						store.send(.suggestionTapped(command))
						isFieldFocused = true
					} label: {
						suggestionRow(command)
					}
					.buttonStyle(.plain)
				}
			}
		}
		.frame(maxHeight: 320)
		.fixedSize(horizontal: false, vertical: true)
	}

	private func suggestionRow(_ command: HomerCommand) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack(spacing: 6) {
				Text(command.isDefault ? "(no command)" : command.command)
					.scaledFont(.body, design: .monospaced, weight: .semibold)
				Text("→ \(command.agent)")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Text(command.promptParam)
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.tertiary)
			}
			if let description = command.description, !description.isEmpty {
				Text(description)
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.frame(maxWidth: .infinity, alignment: .leading)
		.contentShape(Rectangle())
		.help(command.isDefault ? "Any text that names no command runs \(command.agent)" : "Insert \(command.command)")
	}
}
