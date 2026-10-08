import SwiftUI

/// An inline error under a list's toolbar: the last good data stays below it.
package struct HomerErrorBanner: View {
	let message: String

	package init(message: String) {
		self.message = message
	}

	package var body: some View {
		Label(message, systemImage: "exclamationmark.triangle.fill")
			.scaledFont(.callout)
			.foregroundStyle(.red)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)
			.padding(.vertical, 6)
			.background(Color.red.opacity(0.08))
	}
}
