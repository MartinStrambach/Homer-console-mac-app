import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The open conversation: what was asked and answered, in order, with each run between its
/// question and its answer. A run's number opens the run's page.
struct HomerConversationThreadView: View {
	let store: StoreOf<HomerConversationsReducer>

	var body: some View {
		Group {
			if let error = store.threadError {
				VStack(spacing: 0) {
					HomerErrorBanner(message: error)
					Spacer()
				}
			}
			else if store.selectedConversationID == nil {
				EmptyStateView(
					title: "Start a Conversation",
					systemImage: "bubble.left.and.text.bubble.right",
					description: "Write below to run a workflow the way a Slack mention does, or pick a conversation to read or continue it."
				)
			}
			else if store.thread == nil {
				ProgressView("Loading conversation…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else {
				// Not a sheet, so a lazy stack in a scroll view is fine here.
				ScrollViewReader { reader in
					ScrollView {
						LazyVStack(alignment: .leading, spacing: 12) {
							if let conversation = store.thread?.conversation {
								HomerConversationHeader(conversation: conversation)
							}
							ForEach(store.timeline) { item in
								switch item {
								case let .message(message):
									HomerConversationMessageView(message: message)
								case let .run(run):
									HomerConversationRunRow(run: run) { processId in
										store.send(.runTapped(processId: processId))
									}
								}
							}
						}
						.padding()
						.id(store.selectedConversationID)
					}
					.defaultScrollAnchor(.bottom)
					.onChange(of: store.timeline.last?.id) { _, last in
						if let last {
							withAnimation {
								reader.scrollTo(last, anchor: .bottom)
							}
						}
					}
				}
			}
		}
	}
}

struct HomerConversationHeader: View {
	let conversation: HomerConversation

	var body: some View {
		HStack(spacing: 8) {
			Label(conversation.origin.title, systemImage: conversation.origin.systemImage)
			if let channel = conversation.slackChannel {
				HomerChip(channel, monospaced: true)
			}
			HomerChip(conversation.agent)
			if !conversation.workflowCommand.isEmpty {
				HomerChip(conversation.workflowCommand)
			}
			Spacer()
			Text("Started \(HomerFormat.timestamp(conversation.createdAt))")
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
	}
}

struct HomerConversationMessageView: View {
	let message: HomerConversationMessage

	var body: some View {
		switch message.role {
		case .user:
			bubble(alignment: .trailing) {
				Text(HomerMarkdown.inline(message.text))
					.padding(10)
					.homerInset(tint: .accentColor)
			}
		case .assistant:
			bubble(alignment: .leading) {
				Text(HomerMarkdown.inline(message.text))
					.padding(10)
					.frame(maxWidth: .infinity, alignment: .leading)
					.homerCard()
			}
		case .system, .unknown:
			Text(HomerMarkdown.inline(message.text))
				.scaledFont(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: .infinity)
				.textSelection(.enabled)
		}
	}

	private func bubble(alignment: HorizontalAlignment, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: alignment, spacing: 3) {
			HStack(spacing: 6) {
				Text(message.author)
					.fontWeight(.medium)
				Text(HomerFormat.timestamp(message.createdAt))
			}
			.scaledFont(.caption)
			.foregroundStyle(.secondary)
			content()
				.scaledFont(.body)
				.textSelection(.enabled)
		}
		.frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
		.padding(alignment == .trailing ? .leading : .trailing, 60)
	}
}

/// One run of the conversation: its state, the agent, cost and duration, and its processes.
struct HomerConversationRunRow: View {
	let run: HomerConversationRun
	let openProcess: (Int) -> Void

	var body: some View {
		HStack(spacing: 8) {
			if let status = run.state.processStatus {
				HomerStatusBadge(status: status)
			}
			else {
				HomerPill(run.state.title, color: run.state.color)
			}
			if run.state.isActive {
				ProgressView()
					.controlSize(.mini)
			}
			if let command = run.currentCommand, run.state.isActive {
				Text(command)
					.lineLimit(1)
			}
			ForEach(run.processIds, id: \.self) { processId in
				Button("#\(processId)") {
					openProcess(processId)
				}
				.buttonStyle(.link)
				.help("Open run #\(processId)")
			}
			if let questions = run.openQuestions, questions > 0 {
				HomerPill("\(questions)", color: .orange, systemImage: "questionmark.bubble.fill")
					.help("Open questions")
			}
			Spacer()
			if let cost = run.costUsd {
				Text(HomerFormat.cost(cost))
			}
			if let ended = run.endedAt {
				Text(HomerFormat.duration(from: run.startedAt, to: ended))
			}
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.homerInset()
	}
}

extension HomerConversationRun.State {
	/// The color of a state the shared badge has none for.
	var color: Color {
		switch self {
		case .waitingResume, .parked:
			.purple
		case .timeout, .error:
			.red
		default:
			processStatus?.color ?? .gray
		}
	}
}
