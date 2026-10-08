import Sparkle
import SwiftUI

/// The app's Settings window: the console's text size (also in the View menu) and updates.
struct SettingsView: View {
	let updater: SPUUpdater

	@AppStorage("uiFontSize")
	private var uiFontSize = TextSize.default

	var body: some View {
		Form {
			Section("Appearance") {
				HStack {
					Slider(value: $uiFontSize, in: TextSize.minimum...TextSize.maximum, step: 1) {
						Text("Text size: \(Int(uiFontSize)) pt")
					}
					Button("Reset") { uiFontSize = TextSize.default }
						.disabled(uiFontSize == TextSize.default)
				}
			}
			Section("Updates") {
				UpdateSettingsView(updater: updater)
			}
		}
		.formStyle(.grouped)
		.frame(width: 480)
		.fixedSize(horizontal: false, vertical: true)
	}
}
