import HomerCore
import SwiftUI

// Pieces of a run's row that the process list, an agent's run history and a run's page share.

/// A process status as the console's colored badge shows it.
package struct HomerStatusBadge: View {
	let status: HomerProcessStatus

	package init(status: HomerProcessStatus) {
		self.status = status
	}

	package var body: some View {
		HomerPill(status.title, color: status.color)
	}
}

/// A process status as one icon, its name in the tooltip — the compact process list's Status
/// column (`StatusBadge`'s `icon` variant, Homer 1.39).
package struct HomerStatusIcon: View {
	let status: HomerProcessStatus

	package init(status: HomerProcessStatus) {
		self.status = status
	}

	package var body: some View {
		Image(systemName: symbol)
			.foregroundStyle(status.color)
			.symbolEffect(.rotate, isActive: status == .working)
			.scaledFont(.body)
			.help(status.title)
			.accessibilityLabel("Status: \(status.title)")
	}

	private var symbol: String {
		switch status {
		case .created:
			"circle"
		case .working:
			"circle.dashed"
		case .finished:
			"checkmark.circle.fill"
		case .failed:
			"xmark.circle.fill"
		case .killed:
			"nosign"
		case .unknown:
			"questionmark.circle"
		}
	}
}

/// The process list's Status column: the status's icon, why it failed before it started, and
/// its open questions.
package struct HomerProcessStatusCell: View {
	let process: HomerProcess

	package init(process: HomerProcess) {
		self.process = process
	}

	package var body: some View {
		HStack(spacing: 6) {
			HomerStatusIcon(status: process.status)
			if let reason = process.failureReason {
				HomerFailureReasonBadge(reason: reason)
			}
			HomerQuestionCountBadge(count: process.openQuestions ?? 0)
		}
	}
}

/// Why a run ended `FAILED` before any command started, beside its status in a row
/// (`FailureReason`'s `inline` variant, Homer 1.38). Cut to one line; the whole sentence is the
/// tooltip.
package struct HomerFailureReasonBadge: View {
	let reason: String

	package init(reason: String) {
		self.reason = reason
	}

	package var body: some View {
		Label(reason, systemImage: "exclamationmark.triangle.fill")
			.labelStyle(.titleAndIcon)
			.scaledFont(.caption)
			.foregroundStyle(.red)
			.lineLimit(1)
			.truncationMode(.tail)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(.red.opacity(0.12), in: Capsule())
			.help(reason)
			.accessibilityLabel("Failure reason: \(reason)")
	}
}

package struct HomerQuestionCountBadge: View {
	let count: Int

	package init(count: Int) {
		self.count = count
	}

	package var body: some View {
		if count > 0 {
			Label("\(count)", systemImage: "questionmark.bubble.fill")
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.padding(.horizontal, 6)
				.padding(.vertical, 2)
				.background(.orange, in: Capsule())
				.help("\(count) open \(count == 1 ? "question" : "questions") waiting for an answer")
		}
	}
}

/// An agent's `group` beside its name — outlined rather than filled, so it does not read as one
/// of the run's tags.
package struct HomerAgentGroupLabel: View {
	let group: String

	package init(_ group: String) {
		self.group = group
	}

	package var body: some View {
		Label(group, systemImage: "folder")
			.labelStyle(.titleAndIcon)
			.scaledFont(.caption2)
			.foregroundStyle(.secondary)
			.lineLimit(1)
			.truncationMode(.middle)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.overlay {
				Capsule().strokeBorder(Color(nsColor: .separatorColor))
			}
			.help("Agent group \(group)")
	}
}

/// The Duration column (Homer 1.39): how long the whole run has gone on, ticking while it is
/// created or working.
package struct HomerRunDurationView: View {
	let process: HomerProcess

	package init(process: HomerProcess) {
		self.process = process
	}

	package var body: some View {
		if process.isKillable {
			TimelineView(.periodic(from: .now, by: 1)) { context in
				label(now: context.date)
			}
		}
		else {
			label(now: Date())
		}
	}

	private func label(now: Date) -> some View {
		Text(process.duration(now: now).map { HomerFormat.duration(from: 0, to: $0) } ?? "—")
			.scaledFont(.callout)
			.monospacedDigit()
			.foregroundStyle(.secondary)
	}
}

/// The Last Command column: a square per command the run executed (Homer 1.39), then the last
/// one's outcome and label.
package struct HomerLastCommandView: View {
	let process: HomerProcess

	package init(process: HomerProcess) {
		self.process = process
	}

	package var body: some View {
		let dots = process.commandDots
		if let lastCommand = dots.last {
			VStack(alignment: .leading, spacing: 3) {
				HomerCommandDots(dots)
				HStack(spacing: 4) {
					icon(lastCommand.outcome)
					Text(lastCommand.label)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
				.scaledFont(.callout)
				.help(lastCommand.label)
			}
		}
		else {
			Text("-")
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func icon(_ outcome: HomerProcess.LastCommandOutcome) -> some View {
		switch outcome {
		case .running:
			ProgressView()
				.controlSize(.mini)
		case .succeeded:
			Image(systemName: "checkmark")
				.foregroundStyle(.green)
		case .failed:
			Image(systemName: "xmark")
				.foregroundStyle(.red)
		}
	}
}

/// The Runner column: the backend's name, with the pod's phase as a colored dot when the run
/// has a Kubernetes pod.
package struct HomerRunnerView: View {
	let runner: HomerProcess.Runner?

	package init(runner: HomerProcess.Runner?) {
		self.runner = runner
	}

	package var body: some View {
		if let runner {
			HStack(spacing: 6) {
				if runner.podName != nil {
					Circle()
						.fill(Self.color(podPhase: runner.podPhase))
						.frame(width: 8, height: 8)
						.help("Pod \(runner.podName ?? ""): \(runner.podPhase ?? "unknown")")
				}
				Text(runner.displayName)
					.scaledFont(.callout, design: .monospaced)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
		else {
			Text("-")
				.foregroundStyle(.secondary)
		}
	}

	package static func color(podPhase: String?) -> Color {
		switch podPhase {
		case "CREATING", "PENDING", "RUNNING":
			.blue
		case "READY", "SUCCEEDED":
			.green
		case "FAILED":
			.red
		case "KEPT_FOR_DEBUG":
			.orange
		default:
			.gray
		}
	}
}
