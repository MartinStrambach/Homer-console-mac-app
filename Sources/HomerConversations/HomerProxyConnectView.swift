import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The connect form, after the sign-in card: the proxy's URL and this user's token. Inline it is
/// the whole page; as a sheet it has Cancel and, for a connected proxy, Disconnect.
struct HomerProxyConnectView: View {
	@Bindable
	var store: StoreOf<HomerProxyConnectReducer>
	let canCancel: Bool
	var onDisconnect: (() -> Void)?

	init(store: StoreOf<HomerProxyConnectReducer>, canCancel: Bool, onDisconnect: (() -> Void)? = nil) {
		self.store = store
		self.canCancel = canCancel
		self.onDisconnect = onDisconnect
	}

	private enum Field: Hashable {
		case url
		case token
	}

	@FocusState
	private var focusedField: Field?

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				VStack(spacing: 8) {
					Image(systemName: "bubble.left.and.bubble.right.fill")
						.font(.system(size: 40))
						.foregroundStyle(.tint)
					Text("Connect to Proxy")
						.scaledFont(.title2)
						.fontWeight(.semibold)
					Text("The conversation proxy records every chat with this instance’s agents and runs them the way the Slack connector does.")
						.scaledFont(.body)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}

				if let message = store.message {
					Label {
						Text(message)
					} icon: {
						Image(systemName: "key.slash")
							.foregroundStyle(.orange)
					}
					.scaledFont(.callout)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(10)
					.homerInset(tint: .orange)
				}

				VStack(alignment: .leading, spacing: 14) {
					labeledField("Proxy URL") {
						TextField("https://homer-proxy.example.com", text: $store.url)
							.textContentType(.URL)
							.focused($focusedField, equals: .url)
					}
					labeledField("Token") {
						SecureField("Your client token", text: $store.token)
							.focused($focusedField, equals: .token)
					}
					if let error = store.error {
						Text(error)
							.scaledFont(.callout)
							.foregroundStyle(.red)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.textFieldStyle(.roundedBorder)
				.controlSize(.large)
				.onSubmit { store.send(.connectTapped) }

				HStack {
					if canCancel {
						Button("Cancel") { store.send(.cancelTapped) }
							.buttonStyle(.scaledBordered)
							.keyboardShortcut(.cancelAction)
					}
					if let onDisconnect {
						Button("Disconnect", role: .destructive, action: onDisconnect)
							.buttonStyle(.scaledBordered)
							.tint(.red)
							.help("Forget this instance’s proxy and token")
					}
					Spacer()
					if store.isConnecting {
						ProgressView()
							.controlSize(.small)
					}
					Button("Connect") { store.send(.connectTapped) }
						.buttonStyle(.scaledBorderedProminent)
						.keyboardShortcut(.defaultAction)
						.disabled(!store.canConnect)
				}
				.controlSize(.large)
			}
			.padding(28)
			.frame(maxWidth: 440)
			.homerCard(cornerRadius: 20)
			.shadow(color: .black.opacity(0.08), radius: 24, y: 8)
			.padding(40)
			.frame(maxWidth: .infinity)
		}
		.onAppear {
			focusedField = store.url.isEmpty ? .url : .token
		}
	}

	private func labeledField(_ title: String, @ViewBuilder content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title)
				.scaledFont(.callout)
				.fontWeight(.medium)
			content()
		}
	}
}
