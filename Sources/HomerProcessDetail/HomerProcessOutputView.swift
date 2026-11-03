import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// One command's output in a sheet over the process page (`view-artifact-dialog.tsx`):
/// stdout or stderr, an LLM harness command's stdout as the conversation or raw, live while it
/// runs.
struct HomerProcessOutputView: View {
	@Bindable
	var store: StoreOf<HomerProcessOutputReducer>

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(minWidth: 760, idealWidth: 1000, minHeight: 520, idealHeight: 760)
		.task { store.send(.task) }
	}

	private var header: some View {
		HStack(spacing: 10) {
			Text(store.isLiveCommand ? "Live Output — Command \(store.executionIndex)" : "Output — Command \(store.executionIndex)")
				.scaledFont(.headline)

			Picker("Stream", selection: $store.stream) {
				ForEach(HomerOutputStream.allCases, id: \.self) { stream in
					Text(stream.title).tag(stream)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()

			if let path = store.path {
				Text(HomerArtifactPath.fileName(path))
					.scaledFont(.callout, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			if isLive {
				HomerLiveBadge()
			}
			if isLoading {
				ProgressView()
					.controlSize(.small)
			}

			Spacer()

			if store.offersConversation, let harness = store.harness {
				Picker("View", selection: Binding(
					get: { store.effectiveMode },
					set: { store.send(.binding(.set(\.mode, $0))) }
				)) {
					Text(harness.title).tag(HomerProcessOutputReducer.Mode.conversation)
					Text("Raw").tag(HomerProcessOutputReducer.Mode.raw)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}

			Button {
				store.send(.refreshTapped)
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.buttonStyle(.scaledBordered)
			.disabled(!store.showsConversation && (store.path == nil || store.output.isLoading))

			Button("Done") { dismiss() }
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.cancelAction)
		}
		.padding(12)
	}

	private var isLive: Bool {
		if store.showsConversation {
			return store.conversation.hasStarted && !store.conversation.hasEnded && store.conversation.error == nil
		}
		return store.output.hasLoaded && !store.output.isComplete
	}

	private var isLoading: Bool {
		store.showsConversation ? store.conversation.isStreaming && !store.conversation.hasEvents : store.output.isLoading
	}

	@ViewBuilder
	private var content: some View {
		let output = store.output
		if store.showsConversation, let harness = store.harness {
			conversation(harness)
		}
		else if store.path == nil {
			placeholder("No \(store.stream.title.lowercased()) for this command")
		}
		else if !output.hasLoaded {
			if let error = output.error {
				placeholder("Failed to load the output: \(error)", isError: true)
			}
			else {
				ProgressView("Loading output…")
			}
		}
		else {
			VStack(spacing: 0) {
				if let error = output.error {
					HomerErrorBanner(message: error)
				}
				if output.text.isEmpty {
					placeholder(output.isComplete ? "The file is empty" : "Waiting for output…")
						.frame(maxHeight: .infinity)
				}
				else {
					HomerLogTextView(text: output.text, followsEnd: !output.isComplete)
				}
			}
		}
	}

	@ViewBuilder
	private func conversation(_ harness: HomerLLMHarness) -> some View {
		let state = store.conversation
		VStack(spacing: 0) {
			if let error = state.error, state.hasEvents {
				HomerErrorBanner(message: error)
			}
			if state.hasEvents {
				HomerLLMConversationView(
					conversation: state.conversation,
					harness: harness,
					isLive: !state.hasEnded,
					commandStart: store.commandStart,
					accounting: store.llmAccounting
				)
			}
			else if let error = state.error {
				placeholder(error, isError: true)
					.frame(maxHeight: .infinity)
			}
			else if state.hasEnded {
				placeholder("No conversation in this command's output — see Raw")
					.frame(maxHeight: .infinity)
			}
			else {
				ProgressView("Waiting for the conversation…")
					.frame(maxHeight: .infinity)
			}
		}
	}

	private func placeholder(_ text: String, isError: Bool = false) -> some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
			.textSelection(.enabled)
			.padding()
	}
}

// MARK: - Conversation

/// An LLM harness command's conversation (`llm-conversation-view.tsx`): a summary of the run —
/// or, while it runs, a live header — then the assistant's messages and tool calls, each call
/// folded to one line until opened. Only the last message is shown in full.
///
/// A `List`, not a lazy stack in a scroll view: a long conversation inside a sheet would hand
/// the sheet an ever-changing ideal height (README, Sheets).
struct HomerLLMConversationView: View {
	let conversation: HomerLLMConversation
	let harness: HomerLLMHarness
	let isLive: Bool
	let commandStart: Double?
	/// The server's pricing of the finished command, which wins over the harness's own figure
	/// (Codex and opencode report none), as the console's summary prefers it.
	var accounting: HomerLLMAccounting?

	private static let bottomID = "bottom"

	var body: some View {
		ScrollViewReader { proxy in
			List {
				Group {
					if isLive, conversation.outcome == nil {
						liveHeader
					}
					else {
						summary
					}
				}
				.listRowSeparator(.hidden)

				ForEach(Array(conversation.items.enumerated()), id: \.element.id) { index, item in
					row(item, isLastMessage: index == conversation.lastMessageIndex)
						.listRowSeparator(.hidden)
				}

				Color.clear
					.frame(height: 1)
					.id(Self.bottomID)
					.listRowSeparator(.hidden)
			}
			.listStyle(.plain)
			.onChange(of: conversation.items.count) {
				if isLive {
					proxy.scrollTo(Self.bottomID, anchor: .bottom)
				}
			}
		}
	}

	@ViewBuilder
	private func row(_ item: HomerLLMConversation.Item, isLastMessage: Bool) -> some View {
		switch item {
		case let .message(_, text):
			if isLastMessage {
				VStack(alignment: .leading, spacing: 4) {
					Text(harness.title)
						.scaledFont(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
					Text(text)
						.scaledFont(.body)
						.textSelection(.enabled)
						.fixedSize(horizontal: false, vertical: true)
				}
				.padding(.vertical, 4)
			}
			else {
				HomerTranscriptBlock(
					title: "\(harness.title) message",
					titleColor: .secondary,
					preview: String(text.prefix(100)),
					isRunning: false
				) {
					blockText(text, color: .primary)
				}
			}
		case let .tool(tool, result):
			HomerTranscriptBlock(
				title: tool.name,
				titleColor: .blue,
				preview: tool.inputPreview,
				isRunning: isLive && tool.id == conversation.inflightToolID
			) {
				VStack(alignment: .leading, spacing: 8) {
					VStack(alignment: .leading, spacing: 4) {
						caption("Input")
						blockText(tool.input, color: .primary)
					}
					if let result {
						Divider()
						VStack(alignment: .leading, spacing: 4) {
							caption(result.isError ? "Error" : "Result")
							blockText(result.output, color: result.isError ? .red : .green)
						}
					}
				}
			}
		}
	}

	private func caption(_ text: String) -> some View {
		Text(text)
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
	}

	private func blockText(_ text: String, color: Color) -> some View {
		// Tool results can be whole files; past this the raw view is the place to read them.
		let limit = 20000
		let shown = text.count > limit ? String(text.prefix(limit)) + "\n… (\(text.count - limit) more characters — see Raw)" : text
		return Text(shown)
			.scaledFont(.caption, design: .monospaced)
			.foregroundStyle(color)
			.textSelection(.enabled)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var summary: some View {
		HomerFlowLayout(spacing: 16) {
			if let model = conversation.model {
				Text(model)
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			if let outcome = conversation.outcome {
				status(outcome.status)
				// Codex and opencode report tokens only: the server's pricing, once the command has
				// finished, is the figure; the harness's own is the fallback while it runs.
				metric("cost", accounting?.costText ?? outcome.costUsd.map(HomerFormat.cost) ?? "—")
				metric("tokens", Self.tokens(outcome.usage))
				if let duration = outcome.durationMs {
					metric(
						"duration",
						Self.seconds(duration) + (outcome.apiDurationMs.map { " (api \(Self.seconds($0)))" } ?? "")
					)
				}
				if let turns = outcome.turns {
					metric("turns", "\(turns)")
				}
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerInset()
	}

	@ViewBuilder
	private func status(_ status: HomerLLMEvent.TurnEnd.Status) -> some View {
		switch status {
		case .success:
			HomerPill("success", color: .green)
		case let .failed(reason):
			HomerPill("failed", color: .red)
			reasonText(reason)
		case let .stopped(reason):
			// A stop the agent may have asked for, such as a turn limit: not a failure.
			HomerPill("stopped", color: .gray)
			reasonText(reason)
		}
	}

	@ViewBuilder
	private func reasonText(_ reason: String) -> some View {
		if !reason.isEmpty {
			Text(reason)
				.scaledFont(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private var liveHeader: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			HomerFlowLayout(spacing: 16) {
				HomerLiveBadge()
				if let model = conversation.model {
					Text(model)
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.secondary)
				}
				if conversation.turns > 0 {
					Text("turn \(conversation.turns)")
						.scaledFont(.caption)
						.fontWeight(.medium)
				}
				if let commandStart {
					let elapsed = max(0, Int(context.date.timeIntervalSince1970) - Int(commandStart))
					metric("elapsed", String(format: "%d:%02d", elapsed / 60, elapsed % 60))
				}
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerInset()
	}

	private func metric(_ name: String, _ value: String) -> some View {
		Text("\(Text(name).foregroundStyle(.secondary)) \(Text(value).fontWeight(.medium))")
			.scaledFont(.caption)
	}

	private static func seconds(_ milliseconds: Double) -> String {
		String(format: "%.1fs", milliseconds / 1000)
	}

	private static func tokens(_ usage: HomerLLMEvent.TurnEnd.Usage) -> String {
		var text = "in \(usage.input.formatted()) / out \(usage.output.formatted())"
		if usage.cacheRead > 0 {
			text += " / cache↑ \(usage.cacheRead.formatted())"
		}
		if usage.cacheWrite > 0 {
			text += " / cache+ \(usage.cacheWrite.formatted())"
		}
		if usage.reasoning > 0 {
			text += " / reasoning \(usage.reasoning.formatted())"
		}
		return text
	}
}

/// A folded block of the conversation: one line with its title and a preview, opened in place.
struct HomerTranscriptBlock<Content: View>: View {
	let title: String
	let titleColor: Color
	let preview: String
	let isRunning: Bool
	@ViewBuilder
	let content: () -> Content

	@State
	private var isExpanded = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				isExpanded.toggle()
			} label: {
				HStack(spacing: 6) {
					Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
						.scaledFont(.caption2)
						.foregroundStyle(.secondary)
						.frame(width: 10)
					Text(title)
						.scaledFont(.caption, design: .monospaced)
						.fontWeight(.semibold)
						.foregroundStyle(titleColor)
					if isRunning {
						ProgressView()
							.controlSize(.mini)
							.help("Tool running")
					}
					if !isExpanded {
						Text(preview)
							.scaledFont(.caption, design: .monospaced)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.truncationMode(.tail)
					}
					Spacer(minLength: 0)
				}
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			if isExpanded {
				Divider()
				content()
					.padding(10)
			}
		}
		.homerCard(cornerRadius: HomerRadius.inset)
	}
}
