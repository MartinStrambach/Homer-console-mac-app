import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The Chat page: the connect form while the instance has no proxy, otherwise the conversations
/// on the left and the open one on the right, with the composer under it.
package struct HomerConversationsView: View {
	@Bindable
	var store: StoreOf<HomerConversationsReducer>

	package init(store: StoreOf<HomerConversationsReducer>) {
		self.store = store
	}

	package var body: some View {
		Group {
			if store.proxy == nil {
				if let setupStore = store.scope(\.setup, action: \.setup) {
					HomerProxyConnectView(store: setupStore, canCancel: false)
				}
			}
			else {
				page
			}
		}
		// The sheet is the form shown over a connected page (Proxy…); inline it is the page.
		.sheet(
			isPresented: Binding(
				get: { store.proxy != nil && store.setup != nil },
				set: { shown in
					if !shown {
						store.send(.setup(.cancelTapped))
					}
				}
			)
		) {
			if let setupStore = store.scope(\.setup, action: \.setup) {
				HomerProxyConnectView(store: setupStore, canCancel: true) {
					store.send(.disconnectTapped)
				}
				.frame(width: 440)
			}
		}
	}

	private var page: some View {
		VStack(spacing: 0) {
			toolbar
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			HSplitView {
				HomerConversationListView(store: store)
					.frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
				VStack(spacing: 0) {
					HomerConversationThreadView(store: store)
					Divider()
					HomerConversationComposerView(store: store)
				}
				.frame(minWidth: 360, maxWidth: .infinity)
			}
		}
	}

	private var toolbar: some View {
		HStack(spacing: 12) {
			Button("New Conversation", systemImage: "square.and.pencil") {
				store.send(.newConversationTapped)
			}
			.buttonStyle(.scaledBordered)
			.disabled(store.selectedConversationID == nil)
			.help("Start a new conversation")

			Spacer()

			HStack(spacing: 6) {
				Circle()
					.fill(store.isLive ? Color.green : Color.orange)
					.frame(width: 8, height: 8)
				Text(store.isLive ? "Live" : "Polling")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
			}
			.help(store.isLive ? "Following the proxy’s events" : "The event stream is down; the page polls instead")

			if let name = store.accountName {
				Label(name, systemImage: "person.crop.circle")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.help("The proxy knows you as \(name)")
			}

			Button("Proxy…", systemImage: "gearshape") {
				store.send(.changeProxyTapped)
			}
			.buttonStyle(.scaledBordered)
			.help(store.proxy.map { "Connected to \($0.url)" } ?? "")
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
	}
}
