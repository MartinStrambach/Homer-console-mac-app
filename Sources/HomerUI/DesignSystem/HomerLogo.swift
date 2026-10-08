import AppKit
import SwiftUI

/// Homer's own logo — the app icon's drawing without its margin and shadow
/// (`Resources/HomerLogo.png`, written by `scripts/make-icon.swift`). The sign-in form and
/// `HomerConsoleTitle` show it; a host can too, e.g. in its section switcher.
public struct HomerLogo: View {
	private let size: CGFloat

	@Environment(\.uiFontScale)
	private var scale

	/// - Parameter size: its width and height in points, scaled by the UI text size like
	///   `scaledFont(size:)`.
	public init(size: CGFloat) {
		self.size = size
	}

	public var body: some View {
		Image(nsImage: Self.image)
			.resizable()
			.interpolation(.high)
			.aspectRatio(contentMode: .fit)
			.frame(width: size * scale, height: size * scale)
			.accessibilityLabel("Homer")
	}

	private static let image: NSImage = Bundle.module.image(forResource: "HomerLogo") ?? NSImage()
}
