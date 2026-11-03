import AppKit
import SwiftUI

/// The app's light or dark look, chosen in Settings ▸ Appearance. Stored in user defaults
/// (`appearance`); `system` follows macOS.
enum AppAppearance: String, CaseIterable, Identifiable {
	case system
	case light
	case dark

	var id: Self { self }

	var title: String {
		switch self {
		case .system: "System"
		case .light: "Light"
		case .dark: "Dark"
		}
	}

	/// Set on `NSApp` rather than with `preferredColorScheme`: it reaches every window — Settings,
	/// sheets, alerts, menus — and the AppKit views inside them (the code editor, the logs, the web
	/// page), and `nil` goes back to following macOS, which `preferredColorScheme(nil)` does not
	/// always do on macOS once a scheme has been set.
	var nsAppearance: NSAppearance? {
		switch self {
		case .system: nil
		case .light: NSAppearance(named: .aqua)
		case .dark: NSAppearance(named: .darkAqua)
		}
	}
}

extension View {
	/// Applies the stored appearance to the app, now and whenever it changes. Every scene's root
	/// has it, so a change made in Settings applies even while the main window is closed.
	func appAppearance() -> some View {
		modifier(AppAppearanceModifier())
	}
}

private struct AppAppearanceModifier: ViewModifier {
	@AppStorage("appearance")
	private var appearance = AppAppearance.system

	func body(content: Content) -> some View {
		content
			.onChange(of: appearance, initial: true) { _, appearance in
				NSApp.appearance = appearance.nsAppearance
			}
	}
}
