import ComposableArchitecture
import HomerCore
import HomerProcessDetail
import HomerUI
import SwiftUI

/// The console's questions page: open questions, each answered with one of its options or a
/// typed answer (`components/questions/question-item.tsx`).
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
							HomerQuestionCard(store: store, question: question)
						}
					}
					.padding()
				}
			}
		}
	}
}

/// A run's open questions on its page, answered through the instance like the Questions page's.
struct HomerRunQuestionsView: View {
	let store: StoreOf<HomerInstanceReducer>
	let processId: Int

	var body: some View {
		let questions = store.questions.filter { $0.processId == processId }
		if !questions.isEmpty {
			HomerDetailSection("Questions", subtitle: "The agent asked for operator input") {
				VStack(spacing: 10) {
					ForEach(questions) { question in
						HomerQuestionCard(store: store, question: question, showsProcessLink: false)
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

	private var isAnswering: Bool {
		store.answeringQuestionIDs.contains(question.id)
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
				Text("Answering will start **\(dispatch.agentName)**.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}

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

			if let error = store.answerErrors[question.id] {
				Text(error)
					.scaledFont(.callout)
					.foregroundStyle(.red)
			}
		}
		.disabled(isAnswering)
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.5)))
	}

	private var header: some View {
		HStack(spacing: 8) {
			Text("Waiting for answer")
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.padding(.horizontal, 7)
				.padding(.vertical, 2)
				.background(.orange, in: Capsule())

			Text(question.agentName)
				.scaledFont(.callout)
				.fontWeight(.semibold)

			if showsProcessLink {
				Button {
					store.send(.processTapped(processId: question.processId))
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

	private func submitDraft() {
		store.send(.answerTapped(questionId: question.id, answer: draft.wrappedValue))
	}

	/// The question's Markdown, inline formatting only with its line breaks kept. Block syntax
	/// (lists, headings) shows as written, which still reads. Images never load: `Text` does not
	/// fetch them, which is the point — an agent-supplied image URL would otherwise beacon on
	/// view, the reason the console renders only their alt text.
	static func markdown(_ text: String) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
	}
}
