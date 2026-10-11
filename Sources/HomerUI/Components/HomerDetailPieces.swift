import HomerCore
import SwiftUI

// The pieces a detail page is built from — a run's page and an agent's page share them: the
// icon tile its header leads with, the stat tiles under it, titled sections, and the label–value
// grid inside a section.

/// A symbol on a rounded tile of its color: what a detail page's title leads with.
package struct HomerIconTile: View {
	private let systemImage: String
	private let color: Color
	private let size: CGFloat

	@Environment(\.uiFontScale)
	private var scale

	package init(systemImage: String, color: Color, size: CGFloat = 40) {
		self.systemImage = systemImage
		self.color = color
		self.size = size
	}

	package var body: some View {
		let side = size * scale
		RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
			.fill(color.gradient)
			.frame(width: side, height: side)
			.overlay {
				Image(systemName: systemImage)
					.font(.system(size: side * 0.45, weight: .semibold))
					.foregroundStyle(.white)
			}
			.shadow(color: color.opacity(0.3), radius: 4, y: 2)
			.accessibilityHidden(true)
	}
}

/// A figure on a detail page: a small caption over its value, on a card. Lay several out with
/// `HomerStatGrid`.
package struct HomerStat<Value: View>: View {
	private let title: String
	private let systemImage: String
	private let value: Value

	package init(_ title: String, systemImage: String, @ViewBuilder value: () -> Value) {
		self.title = title
		self.systemImage = systemImage
		self.value = value()
	}

	package var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Label(title, systemImage: systemImage)
				.scaledFont(.caption)
				.fontWeight(.medium)
				.foregroundStyle(.secondary)
			value
				.scaledFont(.title3)
				.fontWeight(.semibold)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerCard()
		.accessibilityElement(children: .combine)
	}
}

/// Stat tiles side by side, sharing the row's width.
package struct HomerStatGrid<Content: View>: View {
	private let content: Content

	package init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	package var body: some View {
		HStack(spacing: 12) {
			content
		}
	}
}

/// A titled card of a detail page, as the console's `Card`s.
package struct HomerDetailSection<Content: View>: View {
	let title: String
	let subtitle: String?
	let systemImage: String?
	@ViewBuilder
	let content: () -> Content

	package init(
		_ title: String,
		subtitle: String? = nil,
		systemImage: String? = nil,
		@ViewBuilder content: @escaping () -> Content
	) {
		self.title = title
		self.subtitle = subtitle
		self.systemImage = systemImage
		self.content = content
	}

	package var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				if let systemImage {
					Image(systemName: systemImage)
						.scaledFont(.headline)
						.foregroundStyle(.tint)
				}
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.scaledFont(.headline)
					if let subtitle {
						Text(subtitle)
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
					}
				}
			}
			content()
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerCard()
	}
}

/// A row of a label–value grid: the label secondary, the value beside it on its baseline. Put
/// the rows in a `Grid(alignment: .leadingFirstTextBaseline)`.
package struct HomerGridRow<Value: View>: View {
	private let label: String
	private let value: Value

	package init(_ label: String, @ViewBuilder value: () -> Value) {
		self.label = label
		self.value = value()
	}

	package var body: some View {
		GridRow {
			Text(label)
				.foregroundStyle(.secondary)
			value
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

/// A card that lifts under the pointer: an agent in the grid, anything the user opens.
private struct HomerHoverCard: ViewModifier {
	@State
	private var isHovered = false

	func body(content: Content) -> some View {
		content
			.homerCard(highlight: isHovered ? Color.accentColor : nil)
			.shadow(color: .black.opacity(isHovered ? 0.1 : 0), radius: 10, y: 4)
			.offset(y: isHovered ? -1 : 0)
			.animation(.snappy(duration: 0.2), value: isHovered)
			.onHover { isHovered = $0 }
	}
}

package extension View {
	/// `homerCard()` that lifts and tints its edge under the pointer.
	func homerHoverCard() -> some View {
		modifier(HomerHoverCard())
	}
}

/// A plain button that highlights its row under the pointer and while pressed: a disclosure
/// row's header, a list row.
package struct HomerRowButtonStyle: ButtonStyle {
	package init() {}

	package func makeBody(configuration: Configuration) -> some View {
		Row(configuration: configuration)
	}

	private struct Row: View {
		let configuration: Configuration

		@State
		private var isHovered = false

		var body: some View {
			configuration.label
				.background {
					RoundedRectangle(cornerRadius: HomerRadius.inset, style: .continuous)
						.fill(.fill.secondary)
						.opacity(configuration.isPressed ? 1 : isHovered ? 0.5 : 0)
				}
				.onHover { isHovered = $0 }
		}
	}
}

package extension ButtonStyle where Self == HomerRowButtonStyle {
	static var homerRow: Self {
		HomerRowButtonStyle()
	}
}

package extension HomerProcessStatus {
	/// The status's symbol, for a run's icon tile.
	var systemImage: String {
		switch self {
		case .created:
			"hourglass"
		case .working:
			"gearshape.2.fill"
		case .finished:
			"checkmark"
		case .failed:
			"xmark"
		case .killed:
			"stop.fill"
		case .unknown:
			"questionmark"
		}
	}

	/// The run has stopped for good: its last status change is when it ended.
	var hasEnded: Bool {
		switch self {
		case .finished, .failed, .killed:
			true
		case .created, .working, .unknown:
			false
		}
	}
}
