import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The console's processes page (`app/(dashboard)/processes/page.tsx` and
/// `components/processes/process-table.tsx`): the same filters above the same columns, under
/// the orphan pod sweep's banner on an instance with a Kubernetes runner. A row opens its run's
/// page — double-click, the ID, or the context menu.
struct HomerProcessListView: View {
	@Bindable
	var store: StoreOf<HomerInstanceReducer>

	@State
	private var selection: Set<HomerProcess.ID> = []

	var body: some View {
		VStack(spacing: 0) {
			filterBar
			Divider()
			if let sweep = store.sweep {
				HomerSweepBanner(sweep: sweep)
				Divider()
			}
			if let error = store.processesError {
				HomerErrorBanner(message: error)
				Divider()
			}
			content
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	// MARK: - Filters

	private var filterBar: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				Picker("Runs", selection: $store.rootsOnly) {
					Text("All runs").tag(false)
					Text("Root runs").tag(true)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
				.help("Root runs shows the first run of each flow, with a Flow column summarizing the rest")

				Divider()
					.frame(height: 18)

				ForEach(HomerProcessStatus.filterable, id: \.self) { status in
					statusChip(status)
				}

				if let parent = store.parentFilter {
					removableChip("Children of #\(parent)") { store.send(.parentFilterCleared) }
				}
				ForEach(store.tagFilter, id: \.self) { tag in
					removableChip("tag: \(tag)", monospaced: true) { store.send(.tagFilterRemoved(tag)) }
				}

				if store.hasActiveFilters {
					Button("Clear") { store.send(.filtersCleared) }
						.buttonStyle(.link)
						.scaledFont(.callout)
						.help("Clear the status, agent, parent and tag filters")
				}

				Spacer(minLength: 0)
			}

			HStack(spacing: 10) {
				Picker("Agent", selection: Binding(
					get: { store.agentFilter },
					set: { store.send(.agentFilterChanged($0)) }
				)) {
					Text("All agents").tag(String?.none)
					if !store.agentNames.isEmpty {
						Divider()
					}
					ForEach(store.agentNames, id: \.self) { name in
						Text(name).tag(String?.some(name))
					}
				}
				.labelsHidden()
				.fixedSize()
				.help("Show only one agent's runs")

				Button {
					store.send(.sortOrderToggled)
				} label: {
					Label(store.oldestFirst ? "Oldest first" : "Newest first", systemImage: "arrow.up.arrow.down")
				}
				.buttonStyle(.scaledBordered)

				Spacer()

				if store.hasLoadedProcesses {
					HStack(spacing: 4) {
						Text("Total cost:")
							.foregroundStyle(.secondary)
						Text(HomerFormat.cost(store.listedCostUsd))
							.scaledFont(.callout, design: .monospaced)
							.fontWeight(.medium)
					}
					.help("What the listed runs cost together")
				}
			}
			.scaledFont(.callout)
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	private func statusChip(_ status: HomerProcessStatus) -> some View {
		let isOn = store.statusFilter.contains(status)
		return Button {
			store.send(.statusFilterToggled(status))
		} label: {
			Text(status.rawValue)
				.scaledFont(.caption)
				.fontWeight(.semibold)
				.padding(.horizontal, 9)
				.padding(.vertical, 3)
				.foregroundStyle(isOn ? Color.white : Color.primary)
				.background(isOn ? Color.accentColor : Color.clear, in: Capsule())
				.overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.4)))
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.help(isOn ? "Stop filtering by \(status.title)" : "Show only \(status.title) runs")
	}

	private func removableChip(_ title: String, monospaced: Bool = false, onRemove: @escaping () -> Void) -> some View {
		HStack(spacing: 4) {
			Text(title)
				.scaledFont(.caption, design: monospaced ? .monospaced : .default)
				.lineLimit(1)
				.truncationMode(.middle)
				.frame(maxWidth: 260)
			Button(action: onRemove) {
				Image(systemName: "xmark")
					.scaledFont(.caption2)
					.fontWeight(.bold)
			}
			.buttonStyle(.plain)
			.help("Remove this filter")
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 3)
		.background(Color.secondary.opacity(0.15), in: Capsule())
	}

	// MARK: - Table

	@ViewBuilder
	private var content: some View {
		if !store.hasLoadedProcesses {
			ProgressView("Loading processes…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		else if store.processes.isEmpty {
			EmptyStateView(
				title: "No Processes",
				systemImage: "tray",
				description: store.hasActiveFilters ? "No runs match the filters." : "No runs yet."
			)
		}
		else {
			table
			Divider()
			footer
		}
	}

	private var table: some View {
		Table(store.processes, selection: $selection) {
			TableColumn("ID") { process in
				Button {
					store.send(.processTapped(processId: process.id))
				} label: {
					Text(verbatim: "\(process.id)")
						.scaledFont(.body, design: .monospaced)
				}
				.buttonStyle(.link)
				.help("Open process \(process.id)")
			}
			.width(min: 56, ideal: 70, max: 100)

			TableColumn("Agent") { process in
				VStack(alignment: .leading, spacing: 3) {
					Text(process.agentName)
						.scaledFont(.body)
						.fontWeight(.medium)
						.lineLimit(1)
					if let tags = process.tags, !tags.isEmpty {
						HomerFlowLayout(spacing: 4) {
							ForEach(tags, id: \.self) { tag in
								tagChip(tag)
							}
						}
					}
				}
				.padding(.vertical, 2)
			}
			.width(min: 140, ideal: 220)

			TableColumn("Status") { process in
				HStack(spacing: 6) {
					HomerStatusBadge(status: process.status)
					HomerQuestionCountBadge(count: process.openQuestions ?? 0)
				}
			}
			.width(min: 90, ideal: 130)

			TableColumn("Status Time") { process in
				if let timestamp = process.history.last?.timestamp {
					Text(HomerFormat.timestamp(timestamp))
						.scaledFont(.callout, design: .monospaced)
						.foregroundStyle(.secondary)
				}
				else {
					placeholder
				}
			}
			.width(min: 120, ideal: 140)

			TableColumn("Last Command") { process in
				HomerLastCommandView(process: process)
			}
			.width(min: 100, ideal: 180)

			TableColumn("Cost") { process in
				if let cost = process.costUsd, cost > 0 {
					Text(HomerFormat.cost(cost))
						.scaledFont(.callout, design: .monospaced)
				}
				else {
					placeholder
				}
			}
			.width(min: 60, ideal: 80)

			TableColumn("Runner") { process in
				HomerRunnerView(runner: process.runner)
			}
			.width(min: 70, ideal: 110)

			if store.showsFlowColumn {
				TableColumn("Flow") { process in
					HomerFlowSummaryView(summary: store.flowSummaries[process.id])
				}
				.width(min: 110, ideal: 200)
			}

			TableColumn("Purge") { process in
				if let purgeAt = process.purgeAt {
					Text(HomerFormat.timeUntil(purgeAt, now: Date()))
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.help(HomerFormat.timestamp(purgeAt))
				}
				else {
					Text("—")
						.foregroundStyle(.secondary)
				}
			}
			.width(min: 60, ideal: 80)

			TableColumn("Actions") { process in
				actions(for: process)
			}
			.width(min: 70, ideal: 80)
		}
		.contextMenu(forSelectionType: HomerProcess.ID.self) { ids in
			if let id = ids.first, let process = store.processes[id: id] {
				contextMenu(for: process)
			}
		} primaryAction: { ids in
			if let id = ids.first {
				store.send(.processTapped(processId: id))
			}
		}
	}

	private var placeholder: some View {
		Text("-")
			.foregroundStyle(.secondary)
	}

	private func tagChip(_ tag: String) -> some View {
		Button {
			store.send(.tagTapped(tag))
		} label: {
			Text(tag)
				.scaledFont(.caption2, design: .monospaced)
				.lineLimit(1)
				.truncationMode(.middle)
				.frame(maxWidth: 200)
				.padding(.horizontal, 6)
				.padding(.vertical, 1)
				.background(Color.secondary.opacity(0.15), in: Capsule())
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.help("Show only runs tagged \(tag)")
	}

	@ViewBuilder
	private func actions(for process: HomerProcess) -> some View {
		if store.processActionsInFlight.contains(process.id) {
			ProgressView()
				.controlSize(.small)
		}
		else if process.isKillable, store.user?.canKill(process) == true {
			Button("Kill", role: .destructive) { store.send(.killTapped(processId: process.id)) }
				.buttonStyle(.scaledBordered)
				.controlSize(.small)
				.tint(.red)
		}
		else if process.isRetryable, store.user?.canRetry(process) == true {
			Button {
				store.send(.retryTapped(processId: process.id))
			} label: {
				Label("Retry", systemImage: "arrow.counterclockwise")
			}
			.buttonStyle(.scaledBordered)
			.controlSize(.small)
			.help("Start the run again with the same inputs")
		}
	}

	@ViewBuilder
	private func contextMenu(for process: HomerProcess) -> some View {
		Button {
			store.send(.processTapped(processId: process.id))
		} label: {
			Label("Open Process", systemImage: "doc.text.magnifyingglass")
		}
		if let url = HomerEndpoint.pageURL(baseURL: store.baseURL, path: "processes/\(process.id)") {
			Button {
				NSWorkspace.shared.open(url)
			} label: {
				Label("Open in Browser", systemImage: "safari")
			}
		}
		Button {
			store.send(.showChildRunsTapped(processId: process.id))
		} label: {
			Label("Show Child Runs", systemImage: "arrow.turn.down.right")
		}
		if let parent = process.parentProcessId {
			Button {
				store.send(.processTapped(processId: parent))
			} label: {
				Label("Open Parent #\(parent)", systemImage: "arrow.turn.left.up")
			}
		}
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(String(process.id), forType: .string)
		} label: {
			Label("Copy Process ID", systemImage: "doc.on.doc")
		}
		if process.isKillable, store.user?.canKill(process) == true {
			Divider()
			Button(role: .destructive) {
				store.send(.killTapped(processId: process.id))
			} label: {
				Label("Kill…", systemImage: "xmark.octagon")
			}
		}
		else if process.isRetryable, store.user?.canRetry(process) == true {
			Divider()
			Button {
				store.send(.retryTapped(processId: process.id))
			} label: {
				Label("Retry", systemImage: "arrow.counterclockwise")
			}
		}
	}

	private var footer: some View {
		HStack {
			Text("Showing \(store.processes.count) of \(store.processTotal) processes")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
				.monospacedDigit()
			Spacer()
			if store.canLoadMoreProcesses {
				Button("Load More") { store.send(.loadMoreProcessesTapped) }
					.buttonStyle(.scaledBordered)
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 6)
	}
}

// MARK: - Cells

/// A root run's Flow cell; a dash for rows past the summarized ones or while it loads.
struct HomerFlowSummaryView: View {
	let summary: HomerFlowSummary?

	var body: some View {
		if let summary {
			HStack(spacing: 6) {
				Text("\(summary.runCount) \(summary.runCount == 1 ? "run" : "runs")")
					.scaledFont(.callout, design: .monospaced)
				if summary.costUsd > 0 {
					Text(HomerFormat.cost(summary.costUsd))
						.scaledFont(.callout, design: .monospaced)
						.foregroundStyle(.secondary)
				}
				if let state = summary.state {
					Text(Self.label(state))
						.scaledFont(.caption)
						.foregroundStyle(.white)
						.padding(.horizontal, 5)
						.padding(.vertical, 1)
						.background(Self.color(state), in: RoundedRectangle(cornerRadius: 4))
				}
				if summary.isPartial {
					Text("partial")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.help("Cost and state cover the newest \(HomerFlowSummary.fetchLimit) of \(summary.runCount) runs")
				}
			}
			.lineLimit(1)
		}
		else {
			Text("-")
				.foregroundStyle(.secondary)
		}
	}

	private static func label(_ state: HomerFlowSummary.State) -> String {
		switch state {
		case .question:
			"waiting on a question"
		case .running:
			"running"
		case .failed:
			"failed"
		case .finished:
			"finished"
		}
	}

	private static func color(_ state: HomerFlowSummary.State) -> Color {
		switch state {
		case .question:
			.orange
		case .running:
			.blue
		case .failed:
			.red
		case .finished:
			.green
		}
	}
}

/// The last startup sweep of Kubernetes pods no run owns any more (the console's
/// `sweep-status-banner.tsx`): what it scanned and deleted, and its errors.
struct HomerSweepBanner: View {
	let sweep: HomerHealth.Sweep

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				Text("Orphan pod sweep:")
					.fontWeight(.medium)
				Text(summary)
					.foregroundStyle(.secondary)
				Text("@ \(HomerFormat.timestamp(sweep.ranAt))")
					.scaledFont(.callout, design: .monospaced)
					.foregroundStyle(.secondary)
			}
			ForEach(Array(sweep.errors.enumerated()), id: \.offset) { _, error in
				Text("• \(error)")
					.scaledFont(.caption, design: .monospaced)
					.foregroundStyle(.red)
					.textSelection(.enabled)
			}
		}
		.scaledFont(.callout)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal)
		.padding(.vertical, 6)
		.background((sweep.errors.isEmpty ? Color.secondary : Color.red).opacity(0.08))
		.help(deletedPods)
	}

	private var summary: String {
		var summary = "scanned \(sweep.scanned), deleted \(sweep.deleted.count)"
		if !sweep.errors.isEmpty {
			summary += ", errors \(sweep.errors.count)"
		}
		return summary
	}

	/// The pods it deleted, one per line, for the tooltip.
	private var deletedPods: String {
		sweep.deleted.map { pod in
			let run = pod.processId.map { " (run #\($0))" } ?? ""
			return "\(pod.namespace)/\(pod.name)\(run)"
		}
		.joined(separator: "\n")
	}
}
