import HomerUI
import SwiftUI

/// The console's name and logo, for `HomerConsoleView`'s leading slot where the host has no
/// section switcher of its own to put there (the standalone app).
public struct HomerConsoleTitle: View {
	public init() {}

	public var body: some View {
		Label {
			Text("Homer")
		} icon: {
			HomerLogo(size: 18)
		}
		.scaledFont(.headline)
		.labelStyle(.titleAndIcon)
	}
}
