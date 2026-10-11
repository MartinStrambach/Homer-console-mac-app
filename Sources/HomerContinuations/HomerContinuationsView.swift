import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The console's Continuations page (`app/(dashboard)/continuations/page.tsx`): the pending
/// continuations, then — only when there are any — those that failed to fire, each a card as in
/// `components/continuations/continuation-item.tsx`. A run number opens that run's page.
package struct HomerContinuationsView: View {
	@Bindable
	var store: StoreOf<HomerContinuationsReducer>

	package init(store: StoreOf<HomerContinuationsReducer>) {
		self.store = store
	}

	package var body: some View {
		VStack(spacing: 0) {
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			content
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	@ViewBuilder
	private var content: some View {
		if !store.hasLoaded {
			ProgressView("Loading continuations…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		else if store.pending.isEmpty, store.failed.isEmpty {
			EmptyStateView(
				title: "No Pending Continuations",
				systemImage: "point.3.connected.trianglepath.dotted",
				description: "Parked workflows waiting on a watched run to finish before starting a follow-up agent show up here."
			)
		}
		else {
			// A plain stack, like the questions: a handful of cards, each with links and a button.
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					section(
						"Continuations",
						description: "Parked workflows waiting on a watched run to finish before starting a follow-up agent"
					) {
						if store.pending.isEmpty {
							Text("No pending continuations.")
								.scaledFont(.callout)
								.foregroundStyle(.secondary)
						}
						else {
							ForEach(store.pending) { continuation in
								HomerContinuationCard(store: store, continuation: continuation)
							}
						}
					}

					if !store.failed.isEmpty {
						section(
							"Failed to fire",
							description: "Continuations that never started their follow-up agent, with the reason"
						) {
							ForEach(store.failed) { continuation in
								HomerContinuationCard(store: store, continuation: continuation)
							}
						}
					}
				}
				.padding()
				// A readable measure on a wide window, as the Costs page.
				.frame(maxWidth: 900, alignment: .leading)
				.frame(maxWidth: .infinity)
			}
		}
	}

	private func section(
		_ title: String,
		description: String,
		@ViewBuilder content: () -> some View
	) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.scaledFont(.title3)
					.fontWeight(.semibold)
				Text(description)
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			content()
		}
	}
}

struct HomerContinuationCard: View {
	let store: StoreOf<HomerContinuationsReducer>
	let continuation: HomerContinuation

	private var isCancelling: Bool {
		store.cancellingIDs.contains(continuation.id)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				HomerContinuationStatusBadge(status: continuation.status)
				timestamp("Created", continuation.createdAt)
				Spacer()
				// The run it started is in the chain; when, here.
				if continuation.status == .dispatched, let firedAt = continuation.firedAt {
					timestamp("Started", firedAt)
				}
				if continuation.isCancellable, let expiresAt = continuation.expiresAt {
					timestamp("Expires", expiresAt)
				}
			}

			HStack(alignment: .center, spacing: 12) {
				chain
				Spacer(minLength: 0)
				if continuation.isCancellable {
					if isCancelling {
						ProgressView()
							.controlSize(.small)
					}
					Button("Cancel Continuation", role: .destructive) {
						store.send(.cancelTapped(id: continuation.id))
					}
					.buttonStyle(.scaledBordered)
					.controlSize(.small)
					.tint(.red)
					.disabled(isCancelling)
					.help("Stop \(continuation.agentName) from starting when run #\(continuation.watchedProcessId) finishes")
				}
			}

			if continuation.isCancellable, let error = store.cancelErrors[continuation.id] {
				Text(error)
					.scaledFont(.callout)
					.foregroundStyle(.red)
					.fixedSize(horizontal: false, vertical: true)
			}

			if continuation.status == .failed {
				Label {
					Text("Continuation failed: \(continuation.error ?? "")")
						.textSelection(.enabled)
						.fixedSize(horizontal: false, vertical: true)
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill")
				}
				.scaledFont(.callout)
				.foregroundStyle(.red)
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.homerInset(tint: .red)
			}
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerCard(highlight: continuation.status == .failed ? .red : nil)
		// Settled continuations read as done, as in the console.
		.opacity(continuation.status == .pending ? 1 : 0.8)
		.environment(\.openURL, OpenURLAction { url in
			guard let processId = Self.processId(from: url) else {
				return .systemAction
			}
			store.send(.processTapped(processId: processId))
			return .handled
		})
		.contextMenu {
			contextMenu
		}
	}

	// MARK: - Chain

	/// The continuation as a chain: the run that parked it, the run it waits for, and the agent
	/// it starts — with the run that start made, once dispatched. Wraps on a narrow card.
	private var chain: some View {
		HomerFlowLayout(spacing: 8) {
			node("Origin", systemImage: "arrow.turn.down.right", Self.agentText(continuation.originAgentName, run: continuation.originProcessId))
			arrow
			node("Waits for", systemImage: "hourglass", Self.agentText("Run", run: continuation.watchedProcessId))
			arrow
			node(
				continuation.status == .dispatched ? "Started" : "Then starts",
				systemImage: "play.fill",
				Self.agentText(continuation.agentName, run: continuation.firedProcessId)
			)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(
			"When watched run \(continuation.watchedProcessId) finishes, start \(continuation.agentName). Origin: \(continuation.originAgentName), run \(continuation.originProcessId)."
		)
	}

	private func node(_ caption: String, systemImage: String, _ text: AttributedString) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Label(caption, systemImage: systemImage)
				.scaledFont(.caption)
				.foregroundStyle(.secondary)
			Text(text)
				.scaledFont(.callout)
				.lineLimit(1)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.homerInset()
	}

	private var arrow: some View {
		Image(systemName: "arrow.right")
			.scaledFont(.callout)
			.foregroundStyle(.tertiary)
			.padding(.vertical, 14)
	}

	/// "**starter** #7" — the run number a link the card's `openURL` action turns into
	/// `processTapped`.
	private static func agentText(_ name: String, run processId: Int?) -> AttributedString {
		var text = AttributedString(name)
		text.inlinePresentationIntent = .stronglyEmphasized
		if let processId {
			text += AttributedString(" ")
			text += runLink(processId)
		}
		return text
	}

	// MARK: - Text

	/// "Created 07.10.26 18:52:55" in the card's header.
	private func timestamp(_ title: String, _ epochSeconds: Double) -> some View {
		HStack(spacing: 4) {
			Text(title)
			Text(HomerFormat.timestamp(epochSeconds))
				.scaledFont(.caption, design: .monospaced)
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
	}

	private static func runLink(_ processId: Int) -> AttributedString {
		var text = AttributedString("#\(processId)")
		text.link = processURL(processId)
		return text
	}

	/// A run number's link inside a card's text — never opened as a URL: the card's `openURL`
	/// action reads the id back with `processId(from:)`.
	nonisolated static func processURL(_ processId: Int) -> URL? {
		URL(string: "\(processLinkScheme):\(processId)")
	}

	nonisolated static func processId(from url: URL) -> Int? {
		guard url.scheme == processLinkScheme else {
			return nil
		}
		return Int(url.absoluteString.dropFirst(processLinkScheme.count + 1))
	}

	private nonisolated static let processLinkScheme = "homer-process"

	@ViewBuilder
	private var contextMenu: some View {
		Button {
			store.send(.processTapped(processId: continuation.watchedProcessId))
		} label: {
			Label("Open Watched Run #\(continuation.watchedProcessId)", systemImage: "eye")
		}
		Button {
			store.send(.processTapped(processId: continuation.originProcessId))
		} label: {
			Label("Open Origin Run #\(continuation.originProcessId)", systemImage: "arrow.turn.left.up")
		}
		if let firedProcessId = continuation.firedProcessId {
			Button {
				store.send(.processTapped(processId: firedProcessId))
			} label: {
				Label("Open Started Run #\(firedProcessId)", systemImage: "play")
			}
		}
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(String(continuation.id), forType: .string)
		} label: {
			Label("Copy Continuation ID", systemImage: "doc.on.doc")
		}
		if continuation.isCancellable {
			Divider()
			Button(role: .destructive) {
				store.send(.cancelTapped(id: continuation.id))
			} label: {
				Label("Cancel Continuation…", systemImage: "xmark.octagon")
			}
			.disabled(isCancelling)
		}
	}
}

/// A continuation's status as the console's colored badge shows it.
struct HomerContinuationStatusBadge: View {
	let status: HomerContinuationStatus

	var body: some View {
		HomerPill(status.title, color: color)
			.help("Continuation status: \(status.title)")
	}

	private var color: Color {
		switch status {
		case .pending:
			.orange
		case .dispatching:
			.blue
		case .dispatched:
			.green
		case .failed:
			.red
		case .cancelled, .expired, .unknown:
			.gray
		}
	}
}
