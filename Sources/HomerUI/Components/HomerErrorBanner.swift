import SwiftUI

/// An inline error under a list's toolbar: the last good data stays below it.
package struct HomerErrorBanner: View {
	let message: String

	package init(message: String) {
		self.message = message
	}

	package var body: some View {
		HomerBanner(tint: .red, systemImage: "exclamationmark.triangle.fill") {
			Text(message)
				.textSelection(.enabled)
		}
	}
}

/// A note above a page's content, inset from its edges: an error, a sweep's report.
package struct HomerBanner<Content: View>: View {
	private let tint: Color
	private let systemImage: String
	private let content: Content

	package init(tint: Color, systemImage: String, @ViewBuilder content: () -> Content) {
		self.tint = tint
		self.systemImage = systemImage
		self.content = content()
	}

	package var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 8) {
			Image(systemName: systemImage)
				.foregroundStyle(tint)
			VStack(alignment: .leading, spacing: 4) {
				content
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.scaledFont(.callout)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.homerInset(tint: tint)
		.overlay {
			RoundedRectangle(cornerRadius: HomerRadius.inset, style: .continuous)
				.strokeBorder(tint.opacity(0.25))
		}
		.padding(.horizontal)
		.padding(.vertical, 6)
	}
}
