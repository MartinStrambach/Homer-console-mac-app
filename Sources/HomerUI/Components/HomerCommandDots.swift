import HomerCore
import SwiftUI

/// One small square per command, colored by how it went — the newest last
/// (`workflow-dots.ts`): a workflow's sub runs and, since Homer 1.39, a run's row on the process
/// list. `states` are the console's names: `ok`, `failed`, `running`, anything else muted.
package struct HomerCommandDots: View {
	let states: [String]
	let labels: [String]?

	/// Beyond this the oldest are dropped: the newest and the running ones say the most.
	private static let limit = 40

	package init(states: [String], labels: [String]? = nil) {
		self.states = states
		self.labels = labels
	}

	/// A run's commands as the process list's row shows them (`commandDots`).
	package init(_ dots: [HomerProcess.CommandDot]) {
		self.init(states: dots.map(\.state), labels: dots.map(\.label))
	}

	package var body: some View {
		let shown = Array(states.enumerated().suffix(Self.limit))
		HStack(spacing: 2) {
			ForEach(shown, id: \.offset) { index, state in
				RoundedRectangle(cornerRadius: 1.5)
					.fill(Self.color(state))
					.frame(width: 7, height: 7)
					.opacity(state == "running" ? 0.6 : 1)
					.help(labels.map { "\($0[index]): \(state)" } ?? state)
			}
		}
	}

	package static func color(_ state: String) -> Color {
		switch state {
		case "ok":
			.green
		case "failed":
			.red
		case "running":
			.blue
		default:
			.gray
		}
	}
}

private extension HomerProcess.CommandDot {
	/// The console's name for the dot's state.
	var state: String {
		switch outcome {
		case .succeeded:
			"ok"
		case .failed:
			"failed"
		case .running:
			"running"
		}
	}
}
