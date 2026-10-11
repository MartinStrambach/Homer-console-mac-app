import HomerCore
import SwiftUI

// The console's surfaces and pills: one look for every page's cards, insets, banners and status
// labels, so a page asks for a role (`homerCard()`, `HomerPill`) rather than spelling out radii,
// fills and strokes of its own. Liquid Glass stays in the header — the navigation layer — and the
// content below it uses plain, quiet surfaces, as the system's own apps do.

package enum HomerRadius {
	/// A card: a question, an agent, a section of a run's page.
	package static let card: CGFloat = 12
	/// A box inside a card: an answer, a command's output, a field.
	package static let inset: CGFloat = 8
	/// A small label: a tag, a code chip.
	package static let chip: CGFloat = 5
}

package extension View {
	/// A card on the page: a raised surface with a hairline edge and a soft shadow. `highlight`
	/// draws the edge in a color instead — an open question, a failed run.
	func homerCard(highlight: Color? = nil, cornerRadius: CGFloat = HomerRadius.card) -> some View {
		let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
		return background {
			shape
				.fill(Color(nsColor: .controlBackgroundColor))
				.shadow(color: .black.opacity(0.06), radius: 3, y: 1)
		}
		.overlay {
			shape.strokeBorder(highlight.map { $0.opacity(0.55) } ?? Color(nsColor: .separatorColor).opacity(0.6))
		}
	}

	/// A recessed box inside a card or a page: an answer, a command's output, a note.
	func homerInset(tint: Color? = nil, cornerRadius: CGFloat = HomerRadius.inset) -> some View {
		background {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.fill(tint.map { AnyShapeStyle($0.opacity(0.1)) } ?? AnyShapeStyle(.fill.quaternary))
		}
	}

	/// A text field's well: the text background with a hairline edge, red while it is invalid.
	func homerField(isInvalid: Bool = false, cornerRadius: CGFloat = HomerRadius.inset) -> some View {
		let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
		return background(Color(nsColor: .textBackgroundColor), in: shape)
			.overlay {
				shape.strokeBorder(isInvalid ? Color.red : Color(nsColor: .separatorColor))
			}
	}
}

/// A status label: a colored dot (or icon) and the title on a tint of the same color.
package struct HomerPill: View {
	private let title: String
	private let color: Color
	private let systemImage: String?

	package init(_ title: String, color: Color, systemImage: String? = nil) {
		self.title = title
		self.color = color
		self.systemImage = systemImage
	}

	package var body: some View {
		HStack(spacing: 4) {
			if let systemImage {
				Image(systemName: systemImage)
					.foregroundStyle(color)
			}
			else {
				Circle()
					.fill(color)
					.frame(width: 6, height: 6)
			}
			Text(title)
				.lineLimit(1)
		}
		.scaledFont(.caption)
		.fontWeight(.semibold)
		.padding(.horizontal, 7)
		.padding(.vertical, 2)
		.background(color.opacity(0.14), in: Capsule())
		.overlay(Capsule().strokeBorder(color.opacity(0.3)))
	}
}

/// A small neutral label: a tag, a capability, a cron.
package struct HomerChip: View {
	private let title: String
	private let monospaced: Bool

	package init(_ title: String, monospaced: Bool = false) {
		self.title = title
		self.monospaced = monospaced
	}

	package var body: some View {
		Text(title)
			.scaledFont(.caption2, design: monospaced ? .monospaced : .default)
			.lineLimit(1)
			.truncationMode(.middle)
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background(.fill.tertiary, in: Capsule())
	}
}

package extension HomerProcessStatus {
	/// The status's color: the console's badge colors.
	var color: Color {
		switch self {
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

#Preview {
	VStack(alignment: .leading, spacing: 12) {
		HStack {
			HomerPill("Running", color: .blue)
			HomerPill("Finished", color: .green)
			HomerPill("Failed", color: .red)
			HomerPill("2", color: .orange, systemImage: "questionmark.bubble.fill")
			HomerChip("env:prod", monospaced: true)
		}
		Text("A card")
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.homerCard()
		Text("An open question")
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
			.homerCard(highlight: .orange)
		Text("An inset")
			.padding(10)
			.frame(maxWidth: .infinity, alignment: .leading)
			.homerInset()
	}
	.padding()
	.frame(width: 480)
}
