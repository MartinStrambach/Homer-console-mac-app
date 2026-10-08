import Sparkle
import SwiftUI

/// The Updates section of Settings. They are Sparkle's own preferences, the same ones its
/// second-launch prompt and the update dialog's checkbox set, so nothing here is stored twice.
struct UpdateSettingsView: View {
	@StateObject
	private var viewModel: UpdaterViewModel

	init(updater: SPUUpdater) {
		_viewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Toggle(
				"Check for updates automatically",
				isOn: Binding(
					get: { viewModel.automaticallyChecksForUpdates },
					set: { viewModel.setAutomaticallyChecksForUpdates($0) }
				)
			)

			Text("Checks every 12 hours.")
				.font(.caption)
				.foregroundStyle(.secondary)

			Toggle(
				"Download and install updates automatically",
				isOn: Binding(
					get: { viewModel.allowsAutomaticUpdates && viewModel.automaticallyDownloadsUpdates },
					set: { viewModel.setAutomaticallyDownloadsUpdates($0) }
				)
			)
			.disabled(!viewModel.allowsAutomaticUpdates)

			Text(
				"A downloaded update is installed when you quit Homer Console, and runs from the next launch. Needs automatic checks."
			)
			.font(.caption)
			.foregroundStyle(.secondary)

			HStack {
				Button("Check Now") {
					viewModel.checkForUpdates()
				}
				.disabled(!viewModel.canCheckForUpdates)

				Text(statusText)
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			if !startsUpdater {
				Text("Updates are off in Debug builds.")
					.font(.caption)
					.foregroundStyle(.orange)
			}
		}
		.disabled(!startsUpdater)
	}

	private var statusText: String {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
		guard let date = viewModel.lastUpdateCheckDate else {
			return "Version \(version)"
		}
		return "Version \(version) · last checked \(date.formatted(.relative(presentation: .named)))"
	}
}
