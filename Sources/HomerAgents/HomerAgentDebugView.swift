import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The editor's Debug panel (`debug-command-panel.tsx`): a row per command with Recall and
/// Debug, then the latest debug run's stdout and stderr (`debug-log-panel.tsx`).
struct HomerAgentDebugPanel: View {
	let store: StoreOf<HomerAgentDebugReducer>

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text("DEBUG")
					.scaledFont(.caption)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.tracking(0.8)
				Spacer()
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			Divider()

			commands
			Divider()

			if let run = store.activeRun {
				log(run)
			}
			else {
				Spacer()
			}
		}
	}

	private var commands: some View {
		VStack(alignment: .leading, spacing: 6) {
			if store.commandCount == 0 {
				Text("No commands defined for this agent.")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
			}
			else {
				ScrollView {
					VStack(spacing: 6) {
						ForEach(0 ..< store.commandCount, id: \.self) { index in
							commandRow(index)
						}
					}
				}
				.frame(maxHeight: 220)
				.fixedSize(horizontal: false, vertical: true)
			}
			if let error = store.recallError {
				Text(error)
					.scaledFont(.caption)
					.foregroundStyle(.red)
					.textSelection(.enabled)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(10)
	}

	private func commandRow(_ index: Int) -> some View {
		let hasLast = store.lastParams[index] != nil
		return HStack(spacing: 4) {
			Text("Command #\(index + 1)")
				.scaledFont(.callout, design: .monospaced)
			Spacer()
			if store.recallInFlight == index {
				ProgressView()
					.controlSize(.small)
			}
			Button {
				store.send(.recallTapped(commandIndex: index))
			} label: {
				Image(systemName: "arrow.counterclockwise")
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
			.disabled(!hasLast || store.recallInFlight != nil)
			.help(hasLast ? "Re-run with last submitted params" : "No previous run to recall")
			Button {
				store.send(.runTapped(commandIndex: index))
			} label: {
				Image(systemName: "play.fill")
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
			.help("Debug command \(index + 1)…")
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
		.overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.25)))
	}

	private func log(_ run: HomerAgentDebugReducer.ActiveRun) -> some View {
		VStack(spacing: 0) {
			HStack(spacing: 4) {
				Text("Process")
				Button {
					store.send(.processTapped)
				} label: {
					Text(verbatim: "#\(run.processId)")
				}
				.buttonStyle(.link)
				.help("Open process " + String(run.processId))
				Text("· Command #\(run.commandIndex + 1)")
					.foregroundStyle(.secondary)
				Spacer()
				Button {
					store.send(.processTapped)
				} label: {
					Image(systemName: "arrow.up.forward.square")
				}
				.buttonStyle(.borderless)
				.help("Open process detail")
				Button {
					store.send(.closeRunTapped)
				} label: {
					Image(systemName: "xmark")
				}
				.buttonStyle(.borderless)
				.help("Close log panel")
			}
			.scaledFont(.caption)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			Divider()
			ForEach(HomerOutputStream.allCases, id: \.self) { stream in
				pane(stream, output: run.output(stream))
				if stream != HomerOutputStream.allCases.last {
					Divider()
				}
			}
		}
	}

	private func pane(_ stream: HomerOutputStream, output: HomerAgentDebugReducer.Output) -> some View {
		VStack(spacing: 0) {
			HStack(spacing: 6) {
				Text(stream.rawValue.uppercased())
					.scaledFont(.caption)
					.fontWeight(.medium)
					.tracking(0.8)
				Spacer()
				if output.hasEnded {
					Text("ended")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
				else if output.isTailing {
					HomerLiveBadge()
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 4)
			.background(Color.secondary.opacity(0.08))
			Divider()
			if output.text.isEmpty {
				Text(output.error ?? (output.hasEnded ? "(empty)" : "Waiting for output…"))
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(output.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
					.padding(8)
			}
			else {
				HomerLogTextView(text: output.text, followsEnd: !output.hasEnded)
				if let error = output.error {
					Text(error)
						.scaledFont(.caption)
						.foregroundStyle(.red)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
				}
			}
		}
		.frame(maxHeight: .infinity)
	}
}

/// A command's debug run sheet (`debug-run-dialog.tsx`): query params and environment, a row
/// each, then Run.
struct HomerAgentDebugRunView: View {
	@Bindable
	var store: StoreOf<HomerAgentDebugRunReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 6) {
				Text("Debug Command #\(store.commandIndex + 1)")
					.scaledFont(.title3)
					.fontWeight(.semibold)
				hint("Runs only this command with custom env and query params. A real process is created — same locks and parallel-run slots as a normal run.")
			}

			// A plain stack: a handful of rows, and a lazy one's changing ideal height makes a
			// sheet re-measure itself (README, Sheets).
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					section(
						"Query Params",
						hint: "Values run through the agent's declared transformer and land in the command env under the matching envName."
					) {
						ForEach($store.params) { $row in
							VStack(alignment: .leading, spacing: 3) {
								keyValueRow(key: $row.key, value: $row.value, keyPlaceholder: "param") {
									store.send(.removeParamTapped(id: row.id))
								}
								if let input = store.state.declaredInput(named: row.key) {
									Text("→ \(input.envName) (\(input.transformer.summary))")
										.scaledFont(.caption, design: .monospaced)
										.foregroundStyle(.secondary)
										.padding(.leading, 4)
								}
							}
						}
						addButton("Add query param") { store.send(.addParamTapped) }
					}
					section(
						"Environment",
						hint: "Key/value pairs merged into the command environment. No transformation — the key is the env var name verbatim."
					) {
						ForEach($store.env) { $row in
							keyValueRow(key: $row.key, value: $row.value, keyPlaceholder: "NAME") {
								store.send(.removeEnvTapped(id: row.id))
							}
						}
						addButton("Add env var") { store.send(.addEnvTapped) }
					}

					if let error = store.runError {
						Text(error)
							.scaledFont(.callout)
							.foregroundStyle(.red)
							.textSelection(.enabled)
							.padding(10)
							.frame(maxWidth: .infinity, alignment: .leading)
							.background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.trailing, 8)
			}
			.frame(maxHeight: 420)
			.fixedSize(horizontal: false, vertical: true)

			HStack {
				Spacer()
				Button("Cancel") { store.send(.cancelTapped) }
					.buttonStyle(.scaledBordered)
					.keyboardShortcut(.cancelAction)
				Button {
					store.send(.runTapped)
				} label: {
					Label(store.isRunning ? "Starting…" : "Run", systemImage: "play.fill")
				}
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.defaultAction)
				.disabled(store.isRunning)
			}
		}
		.padding(20)
		.frame(width: 540)
		.disabled(store.isRunning)
	}

	private func section(_ title: String, hint text: String, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 5) {
				Text(title.uppercased())
					.scaledFont(.caption)
					.fontWeight(.medium)
					.foregroundStyle(.secondary)
					.tracking(0.8)
				hint(text)
			}
			content()
		}
	}

	private func hint(_ text: String) -> some View {
		Image(systemName: "questionmark.circle")
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
			.help(text)
			.accessibilityLabel(text)
	}

	private func keyValueRow(
		key: Binding<String>,
		value: Binding<String>,
		keyPlaceholder: String,
		onRemove: @escaping () -> Void
	) -> some View {
		HStack(spacing: 8) {
			TextField(keyPlaceholder, text: key)
			TextField("value", text: value)
			Button(action: onRemove) {
				Image(systemName: "trash")
			}
			.buttonStyle(.borderless)
			.help("Remove row")
		}
		.textFieldStyle(.roundedBorder)
		.scaledFont(.callout, design: .monospaced)
	}

	private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Label(title, systemImage: "plus")
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.scaledBordered)
	}
}
