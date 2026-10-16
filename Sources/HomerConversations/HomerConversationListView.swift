import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The conversations the proxy recorded, newest activity first: where each came from, its
/// title, the last message, and whether a run is still going. Load More reaches older ones.
struct HomerConversationListView: View {
	@Bindable
	var store: StoreOf<HomerConversationsReducer>

	var body: some View {
		Group {
			if !store.hasLoaded, store.conversations.isEmpty {
				if store.loadError == nil {
					ProgressView("Loading conversations…")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
				else {
					Color.clear
				}
			}
			else if store.conversations.isEmpty {
				EmptyStateView(
					title: "No Conversations",
					systemImage: "bubble.left.and.bubble.right",
					description: "Slack threads the connector ran a workflow in, and conversations started here, show up as they happen."
				)
			}
			else {
				// A `List`: rows recycle, so a long history costs nothing.
				List(selection: $store.selectedConversationID) {
					ForEach(store.conversations) { conversation in
						HomerConversationRow(conversation: conversation)
							.tag(conversation.id)
					}
					if store.nextCursor != nil {
						Button("Load More") {
							store.send(.loadMoreTapped)
						}
						.buttonStyle(.scaledBordered)
						.frame(maxWidth: .infinity)
						.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
	}
}

struct HomerConversationRow: View {
	let conversation: HomerConversation

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: conversation.origin.systemImage)
				.foregroundStyle(.secondary)
				.frame(width: 16)
				.padding(.top, 2)
				.help(conversation.origin.title)
			VStack(alignment: .leading, spacing: 3) {
				HStack(alignment: .firstTextBaseline) {
					Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
						.scaledFont(.body)
						.fontWeight(.medium)
						.lineLimit(1)
					Spacer(minLength: 4)
					Text(Date(timeIntervalSince1970: conversation.updatedAt), format: .relative(presentation: .named))
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				if let last = conversation.lastMessage {
					Text("\(last.author): \(last.preview)")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
				HStack(spacing: 6) {
					if conversation.inFlight {
						HomerPill("Running", color: .blue)
					}
					if !conversation.workflowCommand.isEmpty {
						HomerChip(conversation.workflowCommand)
					}
					HomerChip(conversation.agent)
				}
			}
		}
		.padding(.vertical, 4)
	}
}
