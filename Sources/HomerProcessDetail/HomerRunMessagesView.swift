import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The run's inbox (`run-message-panel.tsx`, Homer 1.38): the messages operators sent it, each
/// with whether the run took it, and — while the run can still take one, for who may control
/// it — a box to send another. Return sends; ⌥Return starts a new line.
struct HomerRunMessagesSection: View {
	@Bindable
	var store: StoreOf<HomerProcessDetailReducer>

	var body: some View {
		HomerDetailSection(
			"Messages",
			subtitle: "Messages you send reach the run at its next check",
			systemImage: "envelope"
		) {
			VStack(alignment: .leading, spacing: 10) {
				ForEach(store.messages ?? []) { message in
					HomerRunMessageRow(message: message)
				}
				if store.canSendMessage {
					sendForm
				}
			}
		}
	}

	private var sendForm: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .bottom) {
				TextField("Type a message for the run…", text: $store.messageDraft, axis: .vertical)
					.lineLimit(1 ... 6)
					.textFieldStyle(.roundedBorder)
					.onSubmit { store.send(.sendMessageTapped) }
					.disabled(store.isSendingMessage)
				Button("Send") {
					store.send(.sendMessageTapped)
				}
				.buttonStyle(.scaledBorderedProminent)
				.disabled(store.isSendingMessage || store.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				if store.isSendingMessage {
					ProgressView()
						.controlSize(.small)
				}
			}
			if let error = store.messageError {
				Text(error)
					.scaledFont(.callout)
					.foregroundStyle(.red)
			}
		}
	}
}

/// One sent message: whether the run took it, who sent it and when, then its text — plain text,
/// never Markdown.
private struct HomerRunMessageRow: View {
	let message: HomerRunMessage

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 8) {
				HomerPill(title, color: color)
				if let sender = message.sender {
					Text(sender)
						.foregroundStyle(.secondary)
				}
				Text(HomerFormat.timestamp(message.createdAt))
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
				if let deliveredAt = message.deliveredAt {
					Text("· taken \(HomerFormat.timestamp(deliveredAt))")
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.secondary)
				}
			}
			.scaledFont(.caption)
			Text(verbatim: message.text)
				.scaledFont(.callout)
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(10)
		.homerInset()
	}

	private var title: String {
		switch message.status {
		case .queued:
			"Queued"
		case .delivered:
			"Delivered"
		case .undelivered:
			"Undelivered"
		case .unknown:
			"Unknown"
		}
	}

	private var color: Color {
		switch message.status {
		case .queued:
			.orange
		case .delivered:
			.green
		case .undelivered, .unknown:
			.gray
		}
	}
}
