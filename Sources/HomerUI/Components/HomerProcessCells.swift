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
		Text(status.title)
			.scaledFont(.caption)
			.fontWeight(.semibold)
			.foregroundStyle(.white)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(color, in: Capsule())
	}

	private var color: Color {
		switch status {
		case .working:
			.blue
		case .finished:
			.green
		case .failed:
			.red
		case .killed:
			.orange
		case .created, .unknown:
			.gray
		}
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
				.padding(.vertical, 1)
				.background(.orange, in: Capsule())
				.help("\(count) open \(count == 1 ? "question" : "questions") waiting for an answer")
		}
	}
}

package struct HomerLastCommandView: View {
	let process: HomerProcess

	package init(process: HomerProcess) {
		self.process = process
	}

	package var body: some View {
		if let lastCommand = process.lastCommand {
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
		case .skipped:
			Image(systemName: "minus.circle")
				.foregroundStyle(.secondary)
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
