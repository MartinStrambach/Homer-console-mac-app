import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The Schedules page of the selected instance (the console's `schedules/page.tsx`): its agents
/// that run on a cron, soonest next run first, each with Run Now (fire it now as the cron would).
/// Admins only — the console shows it to no one else, and the instance never tells this reducer
/// it is on screen for anyone else.
package struct HomerSchedulesView: View {
	@Bindable
	var store: StoreOf<HomerAgentsReducer>
	let user: HomerUser

	/// The content's width, which decides whether a schedule's figures sit beside it or under it.
	@State
	private var contentWidth: CGFloat = 0

	package init(store: StoreOf<HomerAgentsReducer>, user: HomerUser) {
		self.store = store
		self.user = user
	}

	package var body: some View {
		Group {
			if store.editor?.openedFrom == .schedules,
			   let editorStore = store.scope(\.editor, action: \.editor)
			{
				HomerAgentEditorView(store: editorStore, user: user, backTitle: store.editorBackTitle)
			}
			else if store.detail?.openedFrom == .schedules,
			        let detailStore = store.scope(\.detail, action: \.detail)
			{
				HomerAgentDetailView(store: detailStore, user: user)
			}
			else {
				schedules
			}
		}
		.modifier(HomerAgentSheets(store: store))
	}

	private var schedules: some View {
		VStack(spacing: 0) {
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			if !store.hasLoaded {
				ProgressView("Loading schedules…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else if store.schedules.isEmpty {
				EmptyStateView(
					title: "No Scheduled Agents",
					systemImage: "calendar.badge.clock",
					description: "Agents with a cron show up here."
				)
			}
			else {
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						Text("Agents that run on a cron, soonest next run first. Run Now fires one as its cron would.")
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
						stats
						LazyVStack(spacing: 10) {
							ForEach(store.schedules) { agent in
								if let cron = agent.cron {
									HomerScheduleRow(
										agent: agent,
										cron: cron,
										isCompact: contentWidth < Self.wideRowWidth,
										isFiring: store.cronRunsInFlight.contains(agent.name),
										store: store
									)
								}
							}
						}
					}
					.padding()
					.frame(maxWidth: 1100, alignment: .leading)
					.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
					.frame(maxWidth: .infinity)
				}
			}
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	/// From this wide on, a schedule's next and last run sit beside the agent, as columns.
	private static let wideRowWidth: CGFloat = 820

	/// The schedules at a glance: how many, which fires next, how many fire within a day, and
	/// which fired last.
	private var stats: some View {
		TimelineView(.periodic(from: .now, by: 30)) { context in
			let schedules = store.schedules
			let now = context.date.timeIntervalSince1970
			let next = schedules.first { $0.cron?.nextRunAt != nil }
			let dueWithinDay = schedules.count { agent in
				agent.cron?.nextRunAt.map { $0 - now <= 24 * 3600 } ?? false
			}
			let lastFired = schedules
				.compactMap { agent in agent.cron?.lastRunAt.map { (name: agent.name, at: $0) } }
				.max { $0.at < $1.at }

			HomerStatGrid {
				HomerStat("Scheduled agents", systemImage: "calendar.badge.clock") {
					Text("\(schedules.count)")
						.monospacedDigit()
				}
				HomerStat("Next up", systemImage: "clock") {
					if let next, let nextRunAt = next.cron?.nextRunAt {
						HStack(alignment: .firstTextBaseline, spacing: 6) {
							Text(next.name)
								.truncationMode(.middle)
							HomerScheduleCountdownText(epochSeconds: nextRunAt)
								.scaledFont(.callout)
								.foregroundStyle(.secondary)
						}
					}
					else {
						Text(verbatim: "—")
					}
				}
				.help(next?.cron?.nextRunAt.map { HomerFormat.timestamp($0) } ?? "")
				HomerStat("Due within 24 h", systemImage: "calendar") {
					Text("\(dueWithinDay)")
						.monospacedDigit()
				}
				HomerStat("Last fired", systemImage: "clock.arrow.circlepath") {
					if let lastFired {
						HStack(alignment: .firstTextBaseline, spacing: 6) {
							Text(lastFired.name)
								.truncationMode(.middle)
							HomerScheduleElapsedText(epochSeconds: lastFired.at)
								.scaledFont(.callout)
								.foregroundStyle(.secondary)
						}
					}
					else {
						Text("Never")
					}
				}
				.help(lastFired.map { HomerFormat.timestamp($0.at) } ?? "")
			}
		}
	}
}

/// One schedule on the Schedules page: the agent with its cron in words and its timezone, when
/// it next runs (a bar filling from the last run), when it last ran (opening that run), and Run
/// Now. The card opens the agent; wide, the runs are columns beside it, narrow, a row under it.
struct HomerScheduleRow: View {
	let agent: HomerAgent
	let cron: HomerAgent.Cron
	let isCompact: Bool
	/// Run Now is waiting on the server.
	let isFiring: Bool
	let store: StoreOf<HomerAgentsReducer>

	@Environment(\.uiFontScale)
	private var scale

	var body: some View {
		Group {
			if isCompact {
				VStack(alignment: .leading, spacing: 14) {
					identity
					HStack(alignment: .top, spacing: 20) {
						nextRun
							.frame(width: 170 * scale, alignment: .leading)
						lastRun
							.frame(width: 170 * scale, alignment: .leading)
						Spacer(minLength: 0)
						runButton
					}
				}
			}
			else {
				// The run columns fill the row's height from the top, so their titles line up
				// however tall each is; the agent and Run Now sit in the middle.
				HStack(alignment: .center, spacing: 20) {
					identity
						.frame(maxWidth: .infinity, alignment: .leading)
					nextRun
						.frame(width: 170 * scale, alignment: .leading)
						.frame(maxHeight: .infinity, alignment: .top)
					lastRun
						.frame(width: 170 * scale, alignment: .leading)
						.frame(maxHeight: .infinity, alignment: .top)
					runButton
				}
				.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerHoverCard()
		.contentShape(RoundedRectangle(cornerRadius: HomerRadius.card, style: .continuous))
		// The whole card opens the agent; its own buttons (Run Now, the last run) still take
		// their clicks first.
		.onTapGesture {
			store.send(.agentTapped(agentName: agent.name))
		}
		.accessibilityElement(children: .contain)
		.accessibilityAction(named: "Open Agent") {
			store.send(.agentTapped(agentName: agent.name))
		}
		.contextMenu {
			contextMenu
		}
	}

	// MARK: - Agent

	private var identity: some View {
		HStack(alignment: .top, spacing: 12) {
			HomerIconTile(systemImage: "calendar.badge.clock", color: .purple, size: 34)

			VStack(alignment: .leading, spacing: 6) {
				Text(agent.name)
					.scaledFont(.title3)
					.fontWeight(.semibold)
					.lineLimit(1)
					.truncationMode(.middle)
					.help("Open the agent: its parameters, workflow graph and run history")
				if let description = agent.description, !description.isEmpty {
					Text(description)
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.help(description)
				}
				schedule
			}
		}
	}

	/// The cron expression, what it means, and its timezone.
	private var schedule: some View {
		HomerFlowLayout(spacing: 8) {
			Text(cron.expression)
				.scaledFont(.caption, design: .monospaced)
				.fontWeight(.medium)
				.foregroundStyle(.purple)
				.padding(.horizontal, 7)
				.padding(.vertical, 2)
				.background(Color.purple.opacity(0.12), in: Capsule())
				.overlay(Capsule().strokeBorder(Color.purple.opacity(0.25)))
				.textSelection(.enabled)
				.help("The cron expression")
			if let summary = cron.summary {
				Text(summary)
					.scaledFont(.callout)
			}
			if !cron.timezone.isEmpty {
				Label(cron.timezone, systemImage: "globe")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
					.help("The schedule's times are in \(cron.timezone)")
			}
		}
	}

	// MARK: - Runs

	private var nextRun: some View {
		VStack(alignment: .leading, spacing: 4) {
			columnTitle("Next run", systemImage: "clock")
			if let nextRunAt = cron.nextRunAt {
				TimelineView(.periodic(from: .now, by: 1)) { context in
					VStack(alignment: .leading, spacing: 5) {
						Text(HomerFormat.timeUntil(nextRunAt, now: context.date))
							.scaledFont(.body)
							.fontWeight(.semibold)
							.monospacedDigit()
							// Soon: within ten minutes.
							.foregroundStyle(nextRunAt - context.date.timeIntervalSince1970 < 600 ? Color.purple : .primary)
						if let progress = cron.progress(at: context.date) {
							HomerScheduleProgressBar(progress: progress)
								.help("\(Int(progress * 100)) % of the way from the last run to the next")
						}
					}
				}
				Text(HomerFormat.timestamp(nextRunAt))
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			else {
				Text("Not planned")
					.scaledFont(.body)
					.foregroundStyle(.secondary)
					.help("The scheduler gives no next run")
			}
		}
	}

	private var lastRun: some View {
		VStack(alignment: .leading, spacing: 4) {
			columnTitle("Last run", systemImage: "clock.arrow.circlepath")
			if let lastRunAt = cron.lastRunAt {
				HomerScheduleElapsedText(epochSeconds: lastRunAt)
					.scaledFont(.body)
					.fontWeight(.semibold)
				HStack(spacing: 6) {
					Text(HomerFormat.timestamp(lastRunAt))
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.secondary)
					if let processId = cron.lastRunProcessId {
						Button {
							store.send(.processTapped(processId: processId))
						} label: {
							Text(verbatim: "#\(processId)")
								.scaledFont(.caption, design: .monospaced)
						}
						.buttonStyle(.link)
						.help("Open process \(processId)")
					}
				}
			}
			else {
				Text("Never")
					.scaledFont(.body)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func columnTitle(_ title: String, systemImage: String) -> some View {
		Label(title, systemImage: systemImage)
			.scaledFont(.caption)
			.fontWeight(.medium)
			.foregroundStyle(.secondary)
	}

	/// While the run is on its way, a spinner in the button's place — the button keeps its width,
	/// so the columns stay in line with the other rows'.
	private var runButton: some View {
		Button {
			store.send(.cronRunTapped(agentName: agent.name))
		} label: {
			Label("Run Now", systemImage: "play.fill")
		}
		.buttonStyle(.scaledBordered)
		.help("Run \(agent.name) now, as its cron would")
		.opacity(isFiring ? 0 : 1)
		.disabled(isFiring)
		.overlay {
			if isFiring {
				ProgressView()
					.controlSize(.small)
					.help("Asking the scheduler to run \(agent.name)")
			}
		}
	}

	// MARK: - Menu

	@ViewBuilder
	private var contextMenu: some View {
		Button {
			store.send(.agentTapped(agentName: agent.name))
		} label: {
			Label("Open Agent", systemImage: "square.stack.3d.up")
		}
		if let processId = cron.lastRunProcessId {
			Button {
				store.send(.processTapped(processId: processId))
			} label: {
				Label("Open Last Run #\(processId)", systemImage: "doc.text.magnifyingglass")
			}
		}
		Button {
			store.send(.cronRunTapped(agentName: agent.name))
		} label: {
			Label("Run Now…", systemImage: "play")
		}
		.disabled(isFiring)
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(cron.expression, forType: .string)
		} label: {
			Label("Copy Cron Expression", systemImage: "doc.on.doc")
		}
	}
}

/// A thin bar filling with how far it is from the last run to the next.
private struct HomerScheduleProgressBar: View {
	let progress: Double

	var body: some View {
		Capsule()
			.fill(.fill.tertiary)
			.frame(height: 4)
			.overlay(alignment: .leading) {
				GeometryReader { proxy in
					Capsule()
						.fill(Color.purple.gradient)
						.frame(width: max(4, proxy.size.width * progress))
				}
			}
			.accessibilityElement()
			.accessibilityLabel("Progress to the next run")
			.accessibilityValue("\(Int(progress * 100)) percent")
	}
}

/// "in 2h 3m" until a moment, counting down every second (`formatTimeUntil`).
struct HomerScheduleCountdownText: View {
	let epochSeconds: Double

	var body: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			Text(HomerFormat.timeUntil(epochSeconds, now: context.date))
				.monospacedDigit()
		}
	}
}

/// "12m ago" since a moment, counting up every second.
struct HomerScheduleElapsedText: View {
	let epochSeconds: Double

	var body: some View {
		TimelineView(.periodic(from: .now, by: 1)) { context in
			Text(HomerScheduleFormat.timeSince(epochSeconds, now: context.date))
				.monospacedDigit()
		}
	}
}
