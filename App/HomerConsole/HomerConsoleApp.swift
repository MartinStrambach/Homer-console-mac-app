import AppKit
import ComposableArchitecture
import HomerFeature
import SwiftUI

/// The Homer console on its own: the `HomerFeature` package Bridge Commander embeds as a section,
/// in a window of its own.
@main
struct HomerConsoleApp: App {
	@State
	private var store = Store(initialState: HomerConsoleReducer.State()) {
		HomerConsoleReducer()
	}

	@AppStorage("uiFontSize")
	private var uiFontSize = TextSize.default

	var body: some Scene {
		Window("Homer Console", id: "main") {
			HomerConsoleView(store: store) {
				HomerConsoleTitle()
			}
			.frame(minWidth: 900, minHeight: 560)
			.homerUIFontScale(TextSize.scale(for: uiFontSize))
			// Once per launch, not with the console's own `onAppear`: the open questions are
			// polled from here on, for the Dock badge.
			.task { store.send(.start) }
			.onChange(of: store.openQuestionCount, initial: true) { _, count in
				NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
			}
		}
		.windowStyle(.hiddenTitleBar)
		.defaultSize(width: 1280, height: 820)
		.commands {
			CommandGroup(after: .toolbar) {
				Button("Bigger Text") { uiFontSize = TextSize.clamped(uiFontSize + 1) }
					.keyboardShortcut("=", modifiers: .command)
					.disabled(uiFontSize >= TextSize.maximum)
				Button("Smaller Text") { uiFontSize = TextSize.clamped(uiFontSize - 1) }
					.keyboardShortcut("-", modifiers: .command)
					.disabled(uiFontSize <= TextSize.minimum)
				Button("Actual Size") { uiFontSize = TextSize.default }
					.keyboardShortcut("0", modifiers: .command)
					.disabled(uiFontSize == TextSize.default)
				Divider()
			}
		}
	}
}

/// The console's text size, as the point size of body text — Bridge Commander's Settings ▸
/// Appearance setting, here in the View menu.
enum TextSize {
	/// macOS's body size: scale 1.
	static let `default`: Double = 13
	static let minimum: Double = 10
	static let maximum: Double = 20

	static func clamped(_ size: Double) -> Double {
		min(max(size, minimum), maximum)
	}

	static func scale(for size: Double) -> CGFloat {
		CGFloat(clamped(size) / `default`)
	}
}
