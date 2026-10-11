import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The console's sign-in card (`app/(auth)/login/page.tsx`): the instance — a field when adding
/// one, its URL otherwise — then username and password.
package struct HomerLoginView: View {
	@Bindable
	var store: StoreOf<HomerSignInReducer>

	package init(store: StoreOf<HomerSignInReducer>) {
		self.store = store
	}

	private enum Field: Hashable {
		case endpoint
		case username
		case password
	}

	@FocusState
	private var focusedField: Field?

	/// "Fill from Passwords" opened the picker for the username, so the picked one is followed by
	/// a second pick for the password.
	@State
	private var awaitsPickedUsername = false

	package var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				VStack(spacing: 8) {
					HomerLogo(size: 64)
					Text(title)
						.scaledFont(.title2)
						.fontWeight(.semibold)
					Text(subtitle)
						.scaledFont(.body)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}

				if store.sessionExpired {
					Label {
						Text("Your session expired. Please sign in again.")
					} icon: {
						Image(systemName: "clock.badge.exclamationmark")
							.foregroundStyle(.orange)
					}
					.scaledFont(.callout)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(10)
					.homerInset(tint: .orange)
				}

				VStack(alignment: .leading, spacing: 14) {
					endpointField

					labeledField("Username") {
						TextField("Enter username", text: $store.username)
							.textContentType(.username)
							.focused($focusedField, equals: .username)
					}

					labeledField("Password") {
						SecureField("Enter password", text: $store.password)
							.textContentType(.password)
							.focused($focusedField, equals: .password)
					}

					if let error = store.loginError {
						Text(error)
							.scaledFont(.callout)
							.foregroundStyle(.red)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.textFieldStyle(.roundedBorder)
				.controlSize(.large)
				.onSubmit { store.send(.signInTapped) }

				HStack {
					if store.canCancel {
						Button("Cancel") { store.send(.cancelTapped) }
							.buttonStyle(.scaledBordered)
							.keyboardShortcut(.cancelAction)
					}
					Button("Fill from Passwords", systemImage: "key.fill", action: fillFromPasswords)
						.buttonStyle(.scaledBordered)
						.help("Choose a login saved in Passwords")
						.disabled(store.isSigningIn)
					Spacer()
					if store.isSigningIn {
						ProgressView()
							.controlSize(.small)
					}
					Button(signInTitle) { store.send(.signInTapped) }
						.buttonStyle(.scaledBorderedProminent)
						.keyboardShortcut(.defaultAction)
						.disabled(store.isSigningIn || store.loginCooldown > 0)
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
		.background(backdrop)
		.onAppear {
			focusedField = store.isAddingInstance && store.endpoint.isEmpty ? .endpoint : .username
		}
		.onChange(of: store.username) { old, new in
			guard awaitsPickedUsername else {
				return
			}
			awaitsPickedUsername = false
			// A picked username arrives whole; a single character is the user typing after
			// dismissing the picker.
			guard old.isEmpty, new.count > 1 else {
				return
			}
			showPasswordsPicker(in: .password, after: .milliseconds(300))
		}
	}

	/// A soft wash of the accent color behind the card.
	private var backdrop: some View {
		RadialGradient(
			colors: [Color.accentColor.opacity(0.14), .clear],
			center: .top,
			startRadius: 0,
			endRadius: 640
		)
		.ignoresSafeArea()
	}

	private var title: String {
		if !store.isAddingInstance {
			"Sign In to \(HomerEndpoint.displayName(of: store.endpoint))"
		}
		else if store.canCancel {
			"Add a Homer Instance"
		}
		else {
			"Sign In to Homer"
		}
	}

	private var subtitle: String {
		store.isAddingInstance
			? "Enter an instance and sign in with your Homer console username and password. Every instance you add stays signed in; switch between them from the header."
			: "Sign in with your Homer console username and password."
	}

	/// The picker fills only the focused field, with the login's username or password by the
	/// field's content type — never its website. With the username remembered one pick is enough;
	/// otherwise the username is picked first and the password right after.
	private func fillFromPasswords() {
		let field: Field = store.username.isEmpty ? .username : .password
		awaitsPickedUsername = field == .username
		showPasswordsPicker(in: field, after: .milliseconds(100))
	}

	private func showPasswordsPicker(in field: Field, after delay: Duration) {
		guard focusedField != field else {
			HomerPasswordAutoFill.showPicker()
			return
		}
		focusedField = field
		Task {
			// The field becomes first responder on a later pass, and the previous picker has to
			// be gone before the next one opens.
			try? await Task.sleep(for: delay)
			HomerPasswordAutoFill.showPicker()
		}
	}

	private var signInTitle: String {
		store.loginCooldown > 0 ? "Wait \(store.loginCooldown) s" : "Sign In"
	}

	@ViewBuilder
	private var endpointField: some View {
		labeledField("Instance") {
			if store.isAddingInstance {
				TextField("https://homer.example.com", text: $store.endpoint)
					.textContentType(.URL)
					.focused($focusedField, equals: .endpoint)
			}
			else {
				// An instance's form is for its own URL; another one is added from the header's
				// instance menu.
				Text(store.endpoint)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 8)
					.padding(.vertical, 6)
					.homerField(cornerRadius: 6)
			}
		}
	}

	private func labeledField(_ title: String, @ViewBuilder field: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.scaledFont(.callout)
				.fontWeight(.medium)
			field()
		}
	}
}
