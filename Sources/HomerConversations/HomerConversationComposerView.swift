import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The composer: the text, the workflow for a new conversation when there is a choice, and
/// Send (⌘↩ — Return alone is a new line).
struct HomerConversationComposerView: View {
	@Bindable
	var store: StoreOf<HomerConversationsReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextEditor(text: $store.draft)
				.scaledFont(.body)
				.scrollContentBackground(.hidden)
				.frame(minHeight: 60, maxHeight: 160)
				.padding(6)
				.homerField()
				.disabled(store.isSending)

			HStack(spacing: 10) {
				if store.picksWorkflow {
					Picker("Workflow", selection: $store.selectedWorkflowCommand) {
						ForEach(store.workflows) { workflow in
							Text(workflow.title).tag(workflow.command)
						}
					}
					.fixedSize()
					.help(workflowDescription)
				}
				else if store.selectedConversationID == nil, let workflow = store.workflows.first {
					Text("Runs \(workflow.agent)")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
				else if let conversation = store.thread?.conversation {
					Text("Continues the conversation with \(conversation.agent)")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
				if let error = store.sendError {
					Text(error)
						.scaledFont(.caption)
						.foregroundStyle(.red)
						.lineLimit(2)
				}
				Spacer()
				if store.isSending {
					ProgressView()
						.controlSize(.small)
				}
				Button("Send") {
					store.send(.sendTapped)
				}
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.return, modifiers: .command)
				.disabled(!store.canSend)
				.help("Send (⌘↩)")
			}
		}
		.padding()
	}

	private var workflowDescription: String {
		store.workflows.first { $0.command == store.selectedWorkflowCommand }?.description ?? ""
	}
}
