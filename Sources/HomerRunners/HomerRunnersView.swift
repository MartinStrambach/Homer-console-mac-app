import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The console's Runners page (`app/(dashboard)/runners/page.tsx`): the configured runners, the
/// external runners' registered instances and the claim queue. Read-only.
package struct HomerRunnersView: View {
	let store: StoreOf<HomerRunnersReducer>

	package init(store: StoreOf<HomerRunnersReducer>) {
		self.store = store
	}

	package var body: some View {
		VStack(spacing: 0) {
			ForEach(store.errorMessages, id: \.self) { message in
				HomerErrorBanner(message: message)
			}
			if store.isLoading {
				ProgressView("Loading runners…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else {
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						Text("Configured runners, registered pull-mode instances and runs waiting for a runner. Read-only.")
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
						stats
						configuredRunners
						if store.runners?.hasExternalRunners == true {
							externalInstances
						}
						claimQueue
					}
					.padding()
					.frame(maxWidth: 1100, alignment: .leading)
					.frame(maxWidth: .infinity)
				}
			}
		}
	}

	// MARK: - Figures

	/// The page at a glance: how many runners, how busy, and whether runs wait for one.
	private var stats: some View {
		HomerStatGrid {
			HomerStat("Runners", systemImage: "server.rack") {
				Text(store.runners.map { "\($0.runners.count)" } ?? "—")
					.monospacedDigit()
			}
			HomerStat("In use", systemImage: "gauge.with.needle") {
				Text(store.runners.map { "\($0.runners.map(\.inUse).reduce(0, +))" } ?? "—")
					.monospacedDigit()
			}
			if store.runners?.hasExternalRunners == true {
				HomerStat("Instances", systemImage: "antenna.radiowaves.left.and.right") {
					Text(store.runners.map { "\($0.externalInstances.count)" } ?? "—")
						.monospacedDigit()
				}
			}
			HomerStat("Pending claims", systemImage: "hourglass") {
				if let queue = store.queue {
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(verbatim: "\(queue.pending)")
							.monospacedDigit()
							.foregroundStyle(queue.pending > 0 ? Color.orange : Color.primary)
						if let oldest = queue.oldestAgeSec, queue.pending > 0 {
							Text("oldest \(HomerRunnerFormat.age(seconds: oldest))")
								.scaledFont(.callout)
								.foregroundStyle(.secondary)
						}
					}
				}
				else {
					Text(verbatim: "—")
				}
			}
		}
	}

	// MARK: - Runners

	private var configuredRunners: some View {
		HomerDetailSection("Configured runners", systemImage: "server.rack") {
			if let runners = store.runners?.runners {
				if runners.isEmpty {
					HomerRunnersEmptyText("No runners configured.")
				}
				else {
					Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
						GridRow {
							Text("Alias")
							Text("Kind")
							Text("Tags")
							Text("In use / concurrency")
								.gridColumnAlignment(.trailing)
						}
						.modifier(HomerRunnersHeaderRow())
						Divider()
						ForEach(runners) { runner in
							GridRow {
								Text(runner.alias)
									.fontWeight(.medium)
									.lineLimit(1)
									.textSelection(.enabled)
								Label(runner.kind, systemImage: Self.systemImage(kind: runner.kind))
									.foregroundStyle(.secondary)
									.lineLimit(1)
								HomerRunnersTags(tags: runner.tags)
								HomerRunnersCapacity(text: runner.capacityText, isFull: runner.load == 1)
							}
						}
					}
					.scaledFont(.body)
				}
			}
			else {
				HomerRunnersPlaceholder(failed: store.runnersError != nil)
			}
		}
	}

	private static func systemImage(kind: String) -> String {
		switch kind {
		case "local": "desktopcomputer"
		case "ssh": "terminal"
		case "kubernetes": "shippingbox"
		case "external": "antenna.radiowaves.left.and.right"
		default: "server.rack"
		}
	}

	private var externalInstances: some View {
		HomerDetailSection("External runner instances", systemImage: "antenna.radiowaves.left.and.right") {
			let instances = store.runners?.externalInstances ?? []
			if instances.isEmpty {
				HomerRunnersEmptyText("No external runner instances registered.")
			}
			else {
				Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
					GridRow {
						Text("Name")
						Text("Domain")
						Text("Tags")
						Text("Sessions / concurrency")
							.gridColumnAlignment(.trailing)
						Text("Last seen")
						Text("Registered")
						Text("State")
					}
					.modifier(HomerRunnersHeaderRow())
					Divider()
					ForEach(instances) { instance in
						GridRow {
							Text(instance.name)
								.fontWeight(.medium)
								.lineLimit(1)
								.textSelection(.enabled)
								.help(instance.instanceId)
							Text(instance.domain)
								.lineLimit(1)
							HomerRunnersTags(tags: instance.tags)
							HomerRunnersCapacity(
								text: instance.capacityText,
								isFull: instance.activeSessions >= instance.concurrency
							)
							HomerElapsedText(epochSeconds: instance.lastSeenAt)
								.foregroundStyle(.secondary)
								.help(HomerFormat.timestamp(instance.lastSeenAt))
							Text(HomerFormat.timestamp(instance.registeredAt))
								.monospacedDigit()
								.foregroundStyle(.secondary)
							if instance.draining {
								HomerPill("Draining", color: .orange)
									.help("Unregistered: takes no new claims, its sessions run to their end.")
							}
							else {
								HomerPill("Active", color: .green)
							}
						}
					}
				}
				.scaledFont(.body)
			}
		}
	}

	// MARK: - Claim queue

	private var claimQueue: some View {
		HomerDetailSection("Claim queue", systemImage: "hourglass") {
			if let queue = store.queue {
				if queue.pending == 0 {
					HomerRunnersEmptyText("No pending claims.")
				}
				else {
					Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
						GridRow {
							Text("Waiting for")
							Text("Pending")
								.gridColumnAlignment(.trailing)
							Text("Oldest")
								.gridColumnAlignment(.trailing)
						}
						.modifier(HomerRunnersHeaderRow())
						Divider()
						ForEach(queue.byFilter) { group in
							GridRow {
								Text(group.filter.description)
									.textSelection(.enabled)
								Text(verbatim: "\(group.pending)")
									.scaledFont(.body, design: .monospaced)
								Text(HomerRunnerFormat.age(seconds: group.oldestAgeSec))
									.scaledFont(.body, design: .monospaced)
							}
						}
					}
					.scaledFont(.body)
				}
			}
			else {
				HomerRunnersPlaceholder(failed: store.queueError != nil)
			}
		}
	}
}

// MARK: - Pieces

/// A table's column titles.
private struct HomerRunnersHeaderRow: ViewModifier {
	func body(content: Content) -> some View {
		content
			.scaledFont(.caption)
			.fontWeight(.medium)
			.foregroundStyle(.secondary)
	}
}

/// A row's tags as chips, or a dash with none.
private struct HomerRunnersTags: View {
	let tags: [String]

	var body: some View {
		if tags.isEmpty {
			Text(verbatim: "—")
				.foregroundStyle(.secondary)
		}
		else {
			HomerFlowLayout(spacing: 4) {
				ForEach(tags, id: \.self) { tag in
					HomerChip(tag, monospaced: true)
				}
			}
		}
	}
}

/// `2 / 4`, digits aligned; orange when every slot is taken, so a runner that new runs have to
/// wait for stands out.
private struct HomerRunnersCapacity: View {
	let text: String
	let isFull: Bool

	var body: some View {
		Text(text)
			.scaledFont(.body, design: .monospaced)
			.foregroundStyle(isFull ? Color.orange : Color.primary)
			.help(isFull ? "Every slot is taken: new runs wait for one." : "")
	}
}

private struct HomerRunnersEmptyText: View {
	let text: String

	init(_ text: String) {
		self.text = text
	}

	var body: some View {
		Text(text)
			.scaledFont(.callout)
			.foregroundStyle(.secondary)
	}
}

/// A card whose data has not arrived: a spinner, or a note once its call failed (the banner above
/// says why).
private struct HomerRunnersPlaceholder: View {
	let failed: Bool

	var body: some View {
		if failed {
			HomerRunnersEmptyText("Not available.")
		}
		else {
			ProgressView()
				.controlSize(.small)
		}
	}
}
