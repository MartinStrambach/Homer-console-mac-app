import HomerCore
import SwiftUI

/// "12m ago" since a moment, counting up every second: a schedule's last fire, a runner
/// instance's last contact.
package struct HomerElapsedText: View {
	let epochSeconds: Double

	package init(epochSeconds: Double) {
		self.epochSeconds = epochSeconds
	}

	package var body: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			Text(HomerFormat.timeSince(epochSeconds, now: context.date))
				.monospacedDigit()
		}
	}
}
