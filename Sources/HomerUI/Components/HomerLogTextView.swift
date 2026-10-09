import AppKit
import SwiftUI

/// "Live" beside output the run is still writing.
package struct HomerLiveBadge: View {
	package init() {}

	package var body: some View {
		Text("Live")
			.scaledFont(.caption)
			.fontWeight(.semibold)
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background(Color.secondary.opacity(0.18), in: Capsule())
	}
}

/// A log as plain monospaced text, in an `NSTextView`: a command's output runs to megabytes,
/// which a SwiftUI `Text` lays out all at once on every change. Text the live tail adds is
/// appended rather than set again, and the view follows the end while it is at the end.
package struct HomerLogTextView: NSViewRepresentable {
	let text: String
	/// Keep the newest line in view as text arrives — unless the user scrolled up.
	let followsEnd: Bool

	package init(text: String, followsEnd: Bool) {
		self.text = text
		self.followsEnd = followsEnd
	}

	@Environment(\.uiFontScale)
	private var scale

	package func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSTextView.scrollableTextView()
		scrollView.hasHorizontalScroller = false
		scrollView.borderType = .noBorder
		if let textView = scrollView.documentView as? NSTextView {
			textView.isEditable = false
			textView.isSelectable = true
			textView.isRichText = false
			textView.usesFindBar = true
			textView.isIncrementalSearchingEnabled = true
			textView.textContainerInset = NSSize(width: 8, height: 8)
			textView.drawsBackground = true
			textView.backgroundColor = .textBackgroundColor
		}
		return scrollView
	}

	package func updateNSView(_ scrollView: NSScrollView, context: Context) {
		guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else {
			return
		}
		let font = NSFont.monospacedSystemFont(ofSize: UIFontScale.pointSize(of: .callout) * scale, weight: .regular)
		let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
		let coordinator = context.coordinator
		let wasAtEnd = isScrolledToEnd(scrollView)

		if coordinator.font != font {
			coordinator.font = font
			storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
		}
		else if text.utf8.starts(with: coordinator.text.utf8) {
			// Byte-wise: `count` and `hasPrefix` walk characters, slow on a long log.
			let added = text.utf8.dropFirst(coordinator.text.utf8.count)
			if !added.isEmpty {
				storage.append(NSAttributedString(string: String(decoding: added, as: UTF8.self), attributes: attributes))
			}
		}
		else {
			storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
		}
		coordinator.text = text

		if followsEnd, wasAtEnd {
			textView.scrollToEndOfDocument(nil)
		}
	}

	package func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	private func isScrolledToEnd(_ scrollView: NSScrollView) -> Bool {
		guard let documentView = scrollView.documentView else {
			return true
		}
		let visible = scrollView.contentView.documentVisibleRect
		return visible.maxY >= documentView.bounds.maxY - 24
	}

	package final class Coordinator {
		var text = ""
		var font: NSFont?
	}
}
