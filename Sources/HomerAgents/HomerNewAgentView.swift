import ComposableArchitecture
import HomerUI
import SwiftUI

/// The New Agent sheet (the console's `new-agent-dialog.tsx`).
struct HomerNewAgentView: View {
	@Bindable
	var store: StoreOf<HomerNewAgentReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Create Agent")
					.scaledFont(.title3)
					.fontWeight(.semibold)
				Text("Creates a new agent directory with a minimal agent.yaml, and opens it in the editor.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("Name")
					.scaledFont(.callout)
					.fontWeight(.medium)
				TextField("my-agent", text: $store.name)
					.textFieldStyle(.roundedBorder)
					.onSubmit { store.send(.createTapped) }
				if let error = store.nameError ?? store.createError {
					Text(error)
						.scaledFont(.callout)
						.foregroundStyle(.red)
						.fixedSize(horizontal: false, vertical: true)
				}
			}

			HStack {
				if store.isCreating {
					ProgressView()
						.controlSize(.small)
					Text("Creating…")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button("Cancel") { store.send(.cancelTapped) }
					.buttonStyle(.scaledBordered)
					.keyboardShortcut(.cancelAction)
				Button {
					store.send(.createTapped)
				} label: {
					Label("Create", systemImage: "plus")
				}
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.defaultAction)
				.disabled(!store.canCreate)
			}
		}
		.padding(20)
		.frame(width: 420)
	}
}
