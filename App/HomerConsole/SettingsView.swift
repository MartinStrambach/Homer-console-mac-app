import Sparkle
import SwiftUI

/// The app's Settings window: the theme, the console's text size (also in the View menu) and updates.
struct SettingsView: View {
	let updater: SPUUpdater

	@AppStorage("uiFontSize")
	private var uiFontSize = TextSize.default

	@AppStorage("appearance")
	private var appearance = AppAppearance.system

	var body: some View {
		Form {
			Section("Appearance") {
				Picker("Theme", selection: $appearance) {
					ForEach(AppAppearance.allCases) { appearance in
						Text(appearance.title).tag(appearance)
					}
				}
				.pickerStyle(.segmented)
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
