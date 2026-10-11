import SwiftUI

/// A header action: an icon on a circle of Liquid Glass. The icon is monochrome, as toolbar icons
/// are on macOS 26; `color` is for an icon whose color means something.
package struct HeaderButton: View {
	private let icon: String
	private let tooltip: String
	private let color: Color
	private let action: () -> Void

	package var body: some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(color)
				.frame(width: 20, height: 20)
		}
		.buttonStyle(.glass)
		.buttonBorderShape(.circle)
		.help(tooltip)
	}

	package init(
		icon: String,
		tooltip: String,
		color: Color = .primary,
		action: @escaping () -> Void
	) {
		self.icon = icon
		self.tooltip = tooltip
		self.color = color
		self.action = action
	}

}

#Preview {
	HStack(spacing: 8) {
		HeaderButton(
			icon: "arrow.clockwise",
			tooltip: "Refresh",
			action: {}
		)
		HeaderButton(
			icon: "xmark.circle.fill",
			tooltip: "Clear",
			action: {}
		)
	}
	.padding()
}
