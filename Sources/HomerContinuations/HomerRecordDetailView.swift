import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// A continuation's or a dispatch's detail sheet: its status and chain, then every field the
/// server keeps — the input that gets the result or answer, the other inputs, the times, the
/// question — with Cancel while it is pending.
struct HomerRecordDetailView: View {
	let store: StoreOf<HomerRecordDetailReducer>

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			ScrollView {
				switch store.record {
				case let .continuation(continuation):
					content(continuation, noun: HomerContinuationKind.noun) {
						HomerGridRow("Watched run") { runLink(continuation.watchedProcessId) }
						if let resumeParam = continuation.resumeParam {
							HomerGridRow("Result input") { monospaced(resumeParam) }
						}
					}
				case let .dispatch(dispatch):
					content(dispatch, noun: HomerDispatchKind.noun) {
						HomerGridRow("Question") {
							HStack(spacing: 6) {
								monospaced(dispatch.questionId)
								copyButton(dispatch.questionId, help: "Copy question ID")
							}
						}
						if let answerParam = dispatch.answerParam {
							HomerGridRow("Answer input") { monospaced(answerParam) }
						}
					}
				}
			}
		}
		// A fixed ideal size: the sheet does not re-measure as the read lands.
		.frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 520)
		.environment(\.openURL, OpenURLAction { url in
			guard let processId = HomerRunLink.processId(from: url) else {
				return .systemAction
			}
			store.send(.processTapped(processId: processId))
			return .handled
		})
		.task { store.send(.task) }
	}

	private var header: some View {
		HStack(spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.scaledFont(.headline)
				Text(subtitle)
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			Spacer()
			if store.isLoading {
				ProgressView()
					.controlSize(.small)
			}
			if store.record.isCancellable {
				Button(role: .destructive) {
					store.send(.cancelTapped)
				} label: {
					Label("Cancel…", systemImage: "xmark.octagon")
						.foregroundStyle(.red)
				}
				.buttonStyle(.scaledBordered)
			}
			Button("Done") { dismiss() }
				.buttonStyle(.scaledBorderedProminent)
				.keyboardShortcut(.cancelAction)
		}
		.padding(12)
	}

	private var title: String {
		switch store.record {
		case let .continuation(continuation):
			"Continuation #\(continuation.id)"
		case let .dispatch(dispatch):
			"Dispatch #\(dispatch.id)"
		}
	}

	private var subtitle: String {
		switch store.record {
		case let .continuation(continuation):
			continuation.sentence
		case let .dispatch(dispatch):
			dispatch.sentence
		}
	}

	private func content<Record: HomerRecordPresentation>(
		_ record: Record,
		noun: String,
		@ViewBuilder rows: () -> some View
	) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(spacing: 8) {
				HomerRecordStatusBadge(status: record.status)
				if record.isCancellable, let expiresAt = record.expiresAt {
					HomerExpiryLabel(expiresAt: expiresAt)
				}
			}
			HomerRecordChain(record: record)

			if record.status == .failed {
				HomerRecordFailure(noun: noun, error: record.error)
			}

			Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
				HomerGridRow("Starts") {
					Text(record.agentName)
						.fontWeight(.semibold)
						.textSelection(.enabled)
				}
				HomerGridRow("Asked by") {
					HStack(spacing: 4) {
						Text(record.originAgentName)
						runLink(record.originProcessId)
					}
				}
				rows()
				HomerGridRow("Created") { time(record.createdAt) }
				if let expiresAt = record.expiresAt {
					HomerGridRow("Expires") { time(expiresAt) }
				}
				if let startedAt = record.startedAt {
					HomerGridRow("Started") { time(startedAt) }
				}
				if let startedProcessId = record.startedProcessId {
					HomerGridRow("Started run") { runLink(startedProcessId) }
				}
				if let error = record.error, record.status != .failed {
					HomerGridRow("Error") {
						Text(error)
							.foregroundStyle(.red)
							.textSelection(.enabled)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
			.scaledFont(.callout)

			params(record.params ?? [:])
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	/// The other inputs, sorted by name; the server masks secrets.
	@ViewBuilder
	private func params(_ params: [String: String]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Inputs")
				.scaledFont(.callout)
				.fontWeight(.semibold)
			if params.isEmpty {
				Text("None besides the one above.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			else {
				Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
					ForEach(params.keys.sorted(), id: \.self) { name in
						GridRow {
							Text(name)
								.foregroundStyle(.secondary)
								.gridColumnAlignment(.trailing)
							Text(params[name] ?? "")
								.textSelection(.enabled)
								.fixedSize(horizontal: false, vertical: true)
						}
					}
				}
				.scaledFont(.callout, design: .monospaced)
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.homerInset()
			}
		}
	}

	private func runLink(_ processId: Int) -> some View {
		Button("#\(processId)") {
			store.send(.processTapped(processId: processId))
		}
		.buttonStyle(.link)
		.help("Open run #\(processId)")
	}

	private func time(_ epochSeconds: Double) -> some View {
		Text(HomerFormat.timestamp(epochSeconds))
			.scaledFont(.callout, design: .monospaced)
			.foregroundStyle(.secondary)
	}

	private func monospaced(_ text: String) -> some View {
		Text(text)
			.scaledFont(.callout, design: .monospaced)
			.textSelection(.enabled)
	}

	private func copyButton(_ text: String, help: String) -> some View {
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(text, forType: .string)
		} label: {
			Image(systemName: "doc.on.doc")
		}
		.buttonStyle(.borderless)
		.help(help)
	}
}
