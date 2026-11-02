import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The Agents page of the selected instance (the console's `agents/page.tsx`): a search (⌘F),
/// a scheduled / not scheduled filter and the group tabs over the agents' cards, Reload for
/// admins, and Run.
/// `user` decides what it offers (Run, Edit, New Agent, Reload, by the user's grants); the
/// server checks every call again.
package struct HomerAgentsView: View {
	@Bindable
	var store: StoreOf<HomerAgentsReducer>
	let user: HomerUser

	@FocusState
	private var isSearchFocused: Bool
	/// The grid's width, for how many columns of cards fit.
	@State
	private var gridWidth: CGFloat = 0

	/// At most this many cards to a row, however wide the window: wider cards rather than more.
	private static let maxColumns = 4
	private static let minCardWidth: CGFloat = 280
	private static let gridSpacing: CGFloat = 10

	package init(store: StoreOf<HomerAgentsReducer>, user: HomerUser) {
		self.store = store
		self.user = user
	}

	package var body: some View {
		Group {
			if store.editor?.openedFrom == .agents,
			   let editorStore = store.scope(\.editor, action: \.editor)
			{
				HomerAgentEditorView(store: editorStore, user: user, backTitle: store.editorBackTitle)
			}
			else if store.detail?.openedFrom == .agents,
			        let detailStore = store.scope(\.detail, action: \.detail)
			{
				HomerAgentDetailView(store: detailStore, user: user)
			}
			else {
				agents
			}
		}
		.modifier(HomerAgentSheets(store: store))
	}

	private var agents: some View {
		VStack(spacing: 0) {
			toolbar
			if !store.groups.isEmpty {
				groupTabs
			}
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			if let error = store.reloadError {
				HomerAgentDismissableBanner(tint: .red, onDismiss: { store.send(.reloadErrorDismissed) }) {
					Label("Reload failed: \(error)", systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.red)
				}
			}
			if let result = store.reloadResult {
				HomerAgentReloadBanner(result: result) { store.send(.reloadResultDismissed) }
			}
			content
		}
	}

	private var toolbar: some View {
		HStack(spacing: 10) {
			HStack(spacing: 6) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)
				TextField("Search agents…", text: $store.searchText)
					.textFieldStyle(.plain)
					.focused($isSearchFocused)
					.onExitCommand {
						store.send(.binding(.set(\.searchText, "")))
					}
				if !store.searchText.isEmpty {
					Button {
						store.send(.binding(.set(\.searchText, "")))
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
					.help("Clear the search")
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(.fill.tertiary, in: Capsule())
			.frame(maxWidth: 360)
			.help("Search agents by name (⌘F); Esc clears")
			.background {
				// Only while the cards are on screen: an agent's page and the editor have their own ⌘F.
				Button("") { isSearchFocused = true }
					.keyboardShortcut("f", modifiers: .command)
					.hidden()
			}

			Picker("Show", selection: $store.scheduleFilter) {
				let counts = store.agentCounts
				ForEach(HomerAgentsReducer.ScheduleFilter.allCases, id: \.self) { filter in
					Text("\(filter.title) \(counts[filter, default: 0])")
						.tag(filter)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()
			.help("Show every agent, or only those with or without a cron")

			Spacer()

			if user.canReloadAgents {
				Button {
					store.send(.reloadTapped)
				} label: {
					Label("Reload", systemImage: "arrow.clockwise")
				}
				.buttonStyle(.scaledBordered)
				.disabled(store.isReloading)
				.help("Read every agent definition from disk again")
				if store.isReloading {
					ProgressView()
						.controlSize(.small)
				}
			}
			if user.canCreateAgents {
				Button {
					store.send(.newAgentTapped)
				} label: {
					Label("New Agent…", systemImage: "plus")
				}
				.buttonStyle(.scaledBordered)
				.help("Create an agent and open it in the editor")
			}
		}
		.scaledFont(.callout)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	/// The console's group tabs: All, then one per agent group, each with how many cards it would
	/// show under the search and the filter. Wrapping, as the console's do, for a factory with many.
	private var groupTabs: some View {
		let counts = store.groupCounts
		let active = store.activeGroup
		return HomerFlowLayout(spacing: 6) {
			groupTab(title: "All", group: nil, count: counts[nil, default: 0], isSelected: active == nil)
				.help("Every agent, those without a group included")
			ForEach(store.groups, id: \.self) { group in
				groupTab(title: group, group: group, count: counts[group, default: 0], isSelected: active == group)
					.help("Only the agents in the group \(group)")
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal)
		.padding(.bottom, 8)
	}

	private func groupTab(title: String, group: String?, count: Int, isSelected: Bool) -> some View {
		Button {
			store.send(.binding(.set(\.selectedGroup, group)))
		} label: {
			HStack(spacing: 4) {
				Text(title)
					.lineLimit(1)
				Text("\(count)")
					.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
					.monospacedDigit()
			}
			.scaledFont(.callout)
			.fontWeight(isSelected ? .semibold : .regular)
			.padding(.horizontal, 10)
			.padding(.vertical, 4)
			.background {
				Capsule()
					.fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.fill.quaternary))
			}
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	@ViewBuilder
	private var content: some View {
		if !store.hasLoaded {
			ProgressView("Loading agents…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		else if store.filteredAgents.isEmpty {
			EmptyStateView(
				title: "No Agents",
				systemImage: "square.stack.3d.up",
				description: emptyDescription
			)
		}
		else {
			ScrollView {
				// Collapsed cards are all one height, so the rows line up; a card shows the rest of
				// itself over its neighbours under the pointer (`HomerAgentCard`).
				LazyVGrid(
					columns: Array(
						repeating: GridItem(.flexible(), spacing: Self.gridSpacing, alignment: .top),
						count: columnCount
					),
					alignment: .leading,
					spacing: Self.gridSpacing
				) {
					ForEach(store.filteredAgents) { agent in
						HomerAgentCard(agent: agent, user: user, store: store)
					}
				}
				.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
				.padding(12)
			}
		}
	}

	/// As many columns as fit at `minCardWidth`, from one up to `maxColumns`.
	private var columnCount: Int {
		let fitting = Int((gridWidth + Self.gridSpacing) / (Self.minCardWidth + Self.gridSpacing))
		return min(Self.maxColumns, max(1, fitting))
	}

	private var emptyDescription: String {
		let inGroup = store.activeGroup.map { " in \($0)" } ?? ""
		return switch (store.searchText.isEmpty, store.scheduleFilter) {
		case (true, .all): "No agents available."
		case (true, .scheduled): "No agent\(inGroup) runs on a cron."
		case (true, .unscheduled): "Every agent\(inGroup) runs on a cron."
		case (false, .all): "No agents\(inGroup) match your search."
		case (false, _): "No agents\(inGroup) match your search and filter."
		}
	}
}

extension HomerAgentsReducer.ScheduleFilter {
	fileprivate var title: String {
		switch self {
		case .all: "All"
		case .scheduled: "Scheduled"
		case .unscheduled: "Not Scheduled"
		}
	}
}

/// The sheets of the Agents and Schedules pages, on either one so that an agent's page shown in
/// place of either can open them: Run, the workflow graph over the cards, and New Agent.
struct HomerAgentSheets: ViewModifier {
	@Bindable
	var store: StoreOf<HomerAgentsReducer>

	func body(content: Content) -> some View {
		content
			.sheet(
				item: $store.scope(\.$runAgent, action: \.runAgent),
				onDismiss: { store.send(.runSheetDismissed) }
			) { runStore in
				HomerRunAgentView(store: runStore)
			}
			.sheet(item: $store.scope(\.$workflowGraph, action: \.workflowGraph)) { graphStore in
				HomerAgentWorkflowGraphView(store: graphStore)
			}
			.sheet(item: $store.scope(\.$newAgent, action: \.newAgent)) { newAgentStore in
				HomerNewAgentView(store: newAgentStore)
			}
	}
}
