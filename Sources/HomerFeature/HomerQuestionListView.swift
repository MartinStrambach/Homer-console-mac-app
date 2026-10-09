import ComposableArchitecture
import HomerCore
import HomerProcessDetail
import HomerUI
import SwiftUI

/// The console's questions page: open questions, each answered with one of its options or a
/// typed answer, or cancelled when answering would start another agent
/// (`components/questions/question-item.tsx`).
struct HomerQuestionListView: View {
	let store: StoreOf<HomerInstanceReducer>

	var body: some View {
		VStack(spacing: 0) {
			if let error = store.questionsError {
				HomerErrorBanner(message: error)
				Divider()
			}
			if !store.hasLoadedQuestions {
				ProgressView("Loading questions…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.questions.isEmpty {
				EmptyStateView(
					title: "No Open Questions",
					systemImage: "checkmark.bubble",
					description: "Questions agents ask while they run show up here."
				)
			}
			else {
				// A plain stack: there are a handful of questions at most (Homer caps them per
				// process), and each card holds a text field, which a recycling list would not keep
				// focus in.
				ScrollView {
					VStack(spacing: 12) {
						ForEach(store.questions) { question in
							HomerQuestionCard(store: store, question: question) { processId in
								store.send(.processTapped(processId: processId))
							}
						}
					}
					.padding()
				}
			}
		}
	}
}

/// Every question a run asked, on its page (the console's `question-panel.tsx`): the open ones
/// answered through the instance like the Questions page's, the others with their answer and
/// what it started. Until the run's own list is read, its open questions stand in.
struct HomerRunQuestionsView: View {
	let store: StoreOf<HomerInstanceReducer>
	let processId: Int

	private var questions: [HomerQuestion] {
		if let runQuestions = store.runQuestions, runQuestions.processId == processId {
			return Array(runQuestions.questions)
		}
		return store.questions.filter { $0.processId == processId }
	}

	var body: some View {
		let questions = questions
		if !questions.isEmpty {
			HomerDetailSection("Questions", subtitle: "The agent asked for operator input") {
				VStack(spacing: 10) {
					ForEach(questions) { question in
						HomerQuestionCard(store: store, question: question, showsProcessLink: false) { processId in
							// Another run opens on the same page, with Back to this one.
							store.send(.processDetail(.presented(.processLinkTapped(processId: processId))))
						}
					}
				}
			}
		}
	}
}

struct HomerQuestionCard: View {
	let store: StoreOf<HomerInstanceReducer>
	let question: HomerQuestion
	/// Off on the process's own page, which it would only open again.
	var showsProcessLink = true
	/// Opens a run: the one that asked, or the one answering started.
	let openProcess: (Int) -> Void

	private var isAnswering: Bool {
		store.answeringQuestionIDs.contains(question.id)
	}

	private var isOpen: Bool {
		question.status == .open
	}

	private var isConfirmingCancel: Binding<Bool> {
		Binding(
			get: { store.questionToCancel == question.id },
			set: { isPresented in
				if !isPresented {
					store.send(.cancelQuestionDismissed)
				}
			}
		)
	}

	private var draft: Binding<String> {
		Binding(
			get: { store.answerDrafts[question.id] ?? "" },
			set: { store.send(.answerDraftChanged(questionId: question.id, text: $0)) }
		)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header

			Text(Self.markdown(question.text))
				.scaledFont(.body)
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)

			if let dispatch = question.dispatch {
				dispatchOutcome(dispatch)
			}

			switch question.status {
			case .open:
				answerControls
			case .answered:
				answer
			case .expired:
				Text("The run ended before this question was answered.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			case .unknown:
				EmptyView()
			}
		}
		.disabled(isAnswering)
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? Color.orange.opacity(0.5) : Color.secondary.opacity(0.25)))
		.opacity(question.status == .expired ? 0.6 : 1)
		.alert("Cancel this question?", isPresented: isConfirmingCancel) {
			Button("Yes, Cancel", role: .destructive) {
				store.send(.cancelQuestionConfirmed)
			}
			Button("Keep Waiting", role: .cancel) {
				store.send(.cancelQuestionDismissed)
			}
		} message: {
			Text("This expires the question and \(question.dispatch?.agentName ?? "its agent") will not start. This cannot be undone.")
		}
	}

	/// What answering starts, or started: the console's three lines.
	@ViewBuilder
	private func dispatchOutcome(_ dispatch: HomerQuestion.Dispatch) -> some View {
		if isOpen {
			Text("Answering will start **\(dispatch.agentName)**.")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
		}
		if let processId = dispatch.startedProcessId {
			HStack(spacing: 4) {
				Text("Started run")
					.foregroundStyle(.secondary)
				Button {
					openProcess(processId)
				} label: {
					Text(verbatim: "#\(processId)")
						.scaledFont(.callout, design: .monospaced)
				}
				.buttonStyle(.link)
				.help("Open the run answering started")
			}
			.scaledFont(.callout)
		}
		if dispatch.hasFailed {
			Text("Dispatch failed: \(dispatch.error ?? "unknown error")")
				.scaledFont(.callout)
				.foregroundStyle(.red)
				.textSelection(.enabled)
		}
	}

	private var answer: some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text("Answer:")
				.fontWeight(.medium)
			Text(question.answer ?? "")
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)
			if let answeredAt = question.answeredAt {
				Text(HomerFormat.timestamp(answeredAt))
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
		}
		.scaledFont(.callout)
		.padding(10)
		.background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
	}

	/// An open question's options, typed answer and Cancel (when answering would start an agent).
	@ViewBuilder
	private var answerControls: some View {
		if !question.options.isEmpty {
			HomerFlowLayout(spacing: 6) {
				ForEach(question.options, id: \.self) { option in
					Button(option) {
						store.send(.answerTapped(questionId: question.id, answer: option))
					}
					.buttonStyle(.scaledBordered)
				}
			}
		}

		HStack {
			TextField(question.options.isEmpty ? "Type an answer…" : "Or type an answer…", text: draft)
				.textFieldStyle(.roundedBorder)
				.onSubmit(submitDraft)
			Button("Send", action: submitDraft)
				.buttonStyle(.scaledBordered)
				.disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			if isAnswering {
				ProgressView()
					.controlSize(.small)
			}
		}

		if question.dispatch?.id != nil {
			HStack {
				Spacer()
				Button("Cancel Question…", role: .destructive) {
					store.send(.cancelQuestionTapped(questionId: question.id))
				}
				.buttonStyle(.scaledBordered)
				.help("Expire the question so \(question.dispatch?.agentName ?? "its agent") never starts")
			}
		}

		if let error = store.answerErrors[question.id] {
			Text(error)
				.scaledFont(.callout)
				.foregroundStyle(.red)
		}
	}

	private var header: some View {
		HStack(spacing: 8) {
			Text(statusTitle)
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.padding(.horizontal, 7)
				.padding(.vertical, 2)
				.background(statusColor, in: Capsule())

			Text(question.agentName)
				.scaledFont(.callout)
				.fontWeight(.semibold)

			if showsProcessLink {
				Button {
					openProcess(question.processId)
				} label: {
					Text(verbatim: "#\(question.processId)")
						.scaledFont(.callout, design: .monospaced)
				}
				.buttonStyle(.link)
				.help("Open the process that asked")
			}

			Spacer()

			Text(question.createdDate, format: .relative(presentation: .named))
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
				.help(question.createdDate.formatted(date: .abbreviated, time: .standard))
		}
	}

	private var statusTitle: String {
		switch question.status {
		case .open:
			"Waiting for answer"
		case .answered:
			"Answered"
		case .expired:
			"Expired"
		case .unknown:
			"Unknown"
		}
	}

	private var statusColor: Color {
		switch question.status {
		case .open:
			.orange
		case .answered:
			.green
		case .expired, .unknown:
			.gray
		}
	}

	private func submitDraft() {
		store.send(.answerTapped(questionId: question.id, answer: draft.wrappedValue))
	}

	/// The question's Markdown, inline formatting only with its line breaks kept. Block syntax
	/// (lists, headings) shows as written, which still reads. Images never load: `Text` does not
	/// fetch them, which is the point — an agent-supplied image URL would otherwise beacon on
	/// view, the reason the console renders only their alt text.
	nonisolated static func markdown(_ text: String) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
	}
}
