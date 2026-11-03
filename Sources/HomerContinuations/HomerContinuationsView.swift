import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The console's Continuations page (`app/(dashboard)/continuations/page.tsx`) and, beside it,
/// the ask-and-dispatches: a section picker, the filters, then the section's cards as in
/// `components/continuations/continuation-item.tsx`. A run number opens that run's page; Details
/// opens the record's sheet.
package struct HomerContinuationsView: View {
	@Bindable
	var store: StoreOf<HomerContinuationsReducer>

	package init(store: StoreOf<HomerContinuationsReducer>) {
		self.store = store
	}

	package var body: some View {
		VStack(spacing: 0) {
			Picker("Section", selection: Binding(
				get: { store.section },
				set: { store.send(.sectionChanged($0)) }
			)) {
				ForEach(HomerContinuationsReducer.Section.allCases, id: \.self) { section in
					Text(title(of: section)).tag(section)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()
			.padding(.horizontal)
			.padding(.top, 10)
			.padding(.bottom, 4)

			switch store.section {
			case .continuations:
				HomerRecordListView(
					store: store.scope(\.continuations, action: \.continuations),
					agentNames: store.agentNames,
					texts: .continuations
				) { store.send(.recordTapped($0)) }
			case .dispatches:
				HomerRecordListView(
					store: store.scope(\.dispatches, action: \.dispatches),
					agentNames: store.agentNames,
					texts: .dispatches
				) { store.send(.recordTapped($0)) }
			}
		}
		.sheet(item: $store.scope(\.$detail, action: \.detail)) { detailStore in
			HomerRecordDetailView(store: detailStore)
		}
	}

	/// A section counts its pending records once it has read them, as the page picker counts the
	/// pending continuations.
	private func title(of section: HomerContinuationsReducer.Section) -> String {
		let count = switch section {
		case .continuations:
			store.continuations.filter == .open && store.continuations.hasLoaded ? store.continuations.pendingTotal : 0
		case .dispatches:
			store.dispatches.filter == .open && store.dispatches.hasLoaded ? store.dispatches.pendingTotal : 0
		}
		return count > 0 ? "\(section.title) (\(count))" : section.title
	}
}

/// The words that set the two lists apart.
struct HomerRecordListTexts {
	var plural: String
	var description: String
	var emptyTitle: String
	var emptyDescription: String
	var emptySystemImage: String
	var pendingTitle: String
	var failedDescription: String

	static let continuations = Self(
		plural: "continuations",
		description: "Parked workflows waiting on a watched run to finish before starting a follow-up agent",
		emptyTitle: "No Pending Continuations",
		emptyDescription: "Parked workflows waiting on a watched run to finish before starting a follow-up agent show up here.",
		emptySystemImage: "point.3.connected.trianglepath.dotted",
		pendingTitle: "Continuations",
		failedDescription: "Continuations that never started their follow-up agent, with the reason"
	)

	static let dispatches = Self(
		plural: "dispatches",
		description: "Questions whose answer starts an agent, soonest to expire first",
		emptyTitle: "No Pending Dispatches",
		emptyDescription: "Questions whose answer will start an agent show up here until someone answers them.",
		emptySystemImage: "arrowshape.turn.up.forward",
		pendingTitle: "Pending dispatches",
		failedDescription: "Answered questions whose agent failed to start, with the reason"
	)
}

/// One list of the page: its filters, then what needs attention (pending, then failed) or the
/// history on a filter, with Load More.
struct HomerRecordListView<Kind: HomerRecordKind>: View where Kind.Record: HomerRecordPresentation {
	@Bindable
	var store: StoreOf<HomerRecordListReducer<Kind>>
	let agentNames: [String]
	let texts: HomerRecordListTexts
	let showDetail: (HomerRecordDetailReducer.Record) -> Void

	var body: some View {
		VStack(spacing: 0) {
			filterBar
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	// MARK: - Filters

	private var filterBar: some View {
		HStack(spacing: 10) {
			Picker("Status", selection: Binding(
				get: { store.filter },
				set: { store.send(.filterChanged($0)) }
			)) {
				Text("Pending & failed").tag(HomerRecordFilter<Kind.Record.Status>.open)
				Text("All statuses").tag(HomerRecordFilter<Kind.Record.Status>.all)
				Divider()
				ForEach(Kind.Record.Status.filterable, id: \.self) { status in
					Text(status.filterTitle).tag(HomerRecordFilter<Kind.Record.Status>.status(status))
				}
			}
			.labelsHidden()
			.fixedSize()
			.help("Pending & failed shows what needs attention; any other choice shows the history, newest first")

			Picker("Agent", selection: Binding(
				get: { store.agentFilter },
				set: { store.send(.agentFilterChanged($0)) }
			)) {
				Text("All agents").tag(String?.none)
				if !agentNames.isEmpty {
					Divider()
				}
				ForEach(agentNames, id: \.self) { name in
					Text(name).tag(String?.some(name))
				}
				// A filter set before the names arrived, or for an agent since removed.
				if let agent = store.agentFilter, !agentNames.contains(agent) {
					Text(agent).tag(String?.some(agent))
				}
			}
			.labelsHidden()
			.fixedSize()
			.help("Show only the \(texts.plural) that start one agent")

			if store.filter != .open || store.agentFilter != nil {
				Button("Clear") {
					store.send(.filterChanged(.open))
					store.send(.agentFilterChanged(nil))
				}
				.buttonStyle(.link)
				.scaledFont(.callout)
				.help("Back to the pending and failed \(texts.plural) of every agent")
			}

			Spacer(minLength: 0)
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		if !store.hasLoaded {
			if store.loadError == nil {
				ProgressView("Loading \(texts.plural)…")
			}
			else {
				Color.clear
			}
		}
		else if store.filter == .open {
			openView
		}
		else {
			historyView
		}
	}

	@ViewBuilder
	private var openView: some View {
		if store.pending.isEmpty, store.failed.isEmpty {
			EmptyStateView(
				title: texts.emptyTitle,
				systemImage: texts.emptySystemImage,
				description: store.agentFilter.map { "Nothing pending or failed starts \($0)." } ?? texts.emptyDescription
			)
		}
		else {
			// A plain stack, like the questions: a handful of cards, each with links and a button.
			scrolling {
				section(texts.pendingTitle, description: texts.description, note: pendingNote) {
					if store.pending.isEmpty {
						Text("No pending \(texts.plural).")
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
					}
					else {
						cards(store.pending.elements)
						if store.pendingTotal > store.pending.count {
							Text("Showing the \(store.pending.count) newest of \(store.pendingTotal) — choose Pending in the status filter to page through them.")
								.scaledFont(.callout)
								.foregroundStyle(.secondary)
						}
					}
				}

				if !store.failed.isEmpty {
					section("Failed to start", description: texts.failedDescription) {
						cards(store.failed.elements)
					}
				}
			}
		}
	}

	/// "2 expire within the hour", in orange; nothing when none do.
	private var pendingNote: Text? {
		let soon = store.pending.filter { $0.isExpiringSoon(now: .now) }.count
		guard soon > 0 else {
			return nil
		}
		return Text("\(soon) \(soon == 1 ? "expires" : "expire") within the hour")
			.foregroundStyle(.orange)
	}

	@ViewBuilder
	private var historyView: some View {
		if store.records.isEmpty {
			EmptyStateView(
				title: "No Matching \(texts.plural.capitalized)",
				systemImage: "line.3.horizontal.decrease.circle",
				description: "No \(texts.plural) match these filters. Settled ones are kept for a week by default."
			)
		}
		else {
			VStack(spacing: 0) {
				scrolling {
					cards(store.records.elements)
				}
				Divider()
				HStack {
					Text("Showing \(store.records.count) of \(store.total) \(texts.plural), newest first")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.monospacedDigit()
					Spacer()
					if store.hasMore {
						Button("Load More") { store.send(.loadMoreTapped) }
							.buttonStyle(.scaledBordered)
					}
				}
				.padding(.horizontal)
				.padding(.vertical, 6)
			}
		}
	}

	private func scrolling(@ViewBuilder content: () -> some View) -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				content()
			}
			.padding()
			// A readable measure on a wide window, as the Costs page.
			.frame(maxWidth: 900, alignment: .leading)
			.frame(maxWidth: .infinity)
		}
	}

	private func cards(_ records: [Kind.Record]) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ForEach(records) { record in
				HomerRecordCard(store: store, record: record, showDetail: showDetail)
			}
		}
	}

	private func section(
		_ title: String,
		description: String,
		note: Text? = nil,
		@ViewBuilder content: () -> some View
	) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.scaledFont(.title3)
					.fontWeight(.semibold)
				HStack(spacing: 6) {
					Text(description)
						.foregroundStyle(.secondary)
					if let note {
						Text(verbatim: "·")
							.foregroundStyle(.tertiary)
						note
							.fontWeight(.medium)
					}
				}
				.scaledFont(.callout)
			}
			content()
		}
	}
}

// MARK: - Card

/// A continuation or dispatch: its status and times, the chain of runs it ties together, Cancel
/// while it is pending, and why it failed.
struct HomerRecordCard<Kind: HomerRecordKind>: View where Kind.Record: HomerRecordPresentation {
	let store: StoreOf<HomerRecordListReducer<Kind>>
	let record: Kind.Record
	let showDetail: (HomerRecordDetailReducer.Record) -> Void

	private var isCancelling: Bool {
		store.cancellingIDs.contains(record.id)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				HomerRecordStatusBadge(status: record.status)
				HomerRecordTimestamp(title: "Created", epochSeconds: record.createdAt)
				Spacer()
				// The run it started is in the chain; when, here.
				if record.status == .dispatched, let startedAt = record.startedAt {
					HomerRecordTimestamp(title: "Started", epochSeconds: startedAt)
				}
				if record.isCancellable, let expiresAt = record.expiresAt {
					HomerExpiryLabel(expiresAt: expiresAt)
				}
				Button {
					showDetail(record.detailRecord)
				} label: {
					Label("Details", systemImage: "info.circle")
				}
				.buttonStyle(.link)
				.scaledFont(.caption)
				.help("Everything about this \(Kind.noun): its inputs, times and runs")
			}

			HStack(alignment: .center, spacing: 12) {
				HomerRecordChain(record: record)
				Spacer(minLength: 0)
				if record.isCancellable {
					if isCancelling {
						ProgressView()
							.controlSize(.small)
					}
					Button("Cancel \(Kind.noun.capitalized)", role: .destructive) {
						store.send(.cancelTapped(id: record.id))
					}
					.buttonStyle(.scaledBordered)
					.controlSize(.small)
					.tint(.red)
					.disabled(isCancelling)
					.help(record.cancelHelp)
				}
			}

			if record.isCancellable, let error = store.cancelErrors[record.id] {
				Text(error)
					.scaledFont(.callout)
					.foregroundStyle(.red)
					.fixedSize(horizontal: false, vertical: true)
			}

			if record.status == .failed {
				HomerRecordFailure(noun: Kind.noun, error: record.error)
			}
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerCard(highlight: record.status == .failed ? .red : nil)
		// Settled records read as done, as in the console.
		.opacity(record.status == .pending ? 1 : 0.8)
		.environment(\.openURL, OpenURLAction { url in
			guard let processId = HomerRunLink.processId(from: url) else {
				return .systemAction
			}
			store.send(.processTapped(processId: processId))
			return .handled
		})
		.contextMenu {
			Button {
				showDetail(record.detailRecord)
			} label: {
				Label("Show Details", systemImage: "info.circle")
			}
			Divider()
			ForEach(record.runs, id: \.processId) { run in
				Button {
					store.send(.processTapped(processId: run.processId))
				} label: {
					Label("Open \(run.title) #\(run.processId)", systemImage: run.systemImage)
				}
			}
			Divider()
			Button {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(String(record.id), forType: .string)
			} label: {
				Label("Copy \(Kind.noun.capitalized) ID", systemImage: "doc.on.doc")
			}
			if record.isCancellable {
				Divider()
				Button(role: .destructive) {
					store.send(.cancelTapped(id: record.id))
				} label: {
					Label("Cancel \(Kind.noun.capitalized)…", systemImage: "xmark.octagon")
				}
				.disabled(isCancelling)
			}
		}
	}
}

// MARK: - Pieces

/// What a card and the detail sheet draw of a record beyond what `HomerDeferredStart` holds:
/// the chain of runs it ties together, in words and as nodes.
protocol HomerRecordPresentation: HomerDeferredStart {
	var chain: [HomerChainNode] { get }
	/// The chain as a sentence — its accessibility label.
	var sentence: String { get }
	/// The runs it names, for the context menu.
	var runs: [HomerRecordRun] { get }
	var cancelHelp: String { get }
	var detailRecord: HomerRecordDetailReducer.Record { get }
}

struct HomerChainNode {
	var caption: String
	var systemImage: String
	/// An agent's name, or what stands for the node.
	var name: String
	var processId: Int?
}

struct HomerRecordRun {
	var title: String
	var systemImage: String
	var processId: Int
}

extension HomerContinuation: HomerRecordPresentation {
	var chain: [HomerChainNode] {
		[
			HomerChainNode(caption: "Origin", systemImage: "arrow.turn.down.right", name: originAgentName, processId: originProcessId),
			HomerChainNode(caption: "Waits for", systemImage: "hourglass", name: "Run", processId: watchedProcessId),
			HomerChainNode(
				caption: status == .dispatched ? "Started" : "Then starts",
				systemImage: "play.fill",
				name: agentName,
				processId: firedProcessId
			),
		]
	}

	var sentence: String {
		"When watched run \(watchedProcessId) finishes, start \(agentName). Origin: \(originAgentName), run \(originProcessId)."
	}

	var runs: [HomerRecordRun] {
		[
			HomerRecordRun(title: "Watched Run", systemImage: "eye", processId: watchedProcessId),
			HomerRecordRun(title: "Origin Run", systemImage: "arrow.turn.left.up", processId: originProcessId),
		] + (firedProcessId.map { [HomerRecordRun(title: "Started Run", systemImage: "play", processId: $0)] } ?? [])
	}

	var cancelHelp: String {
		"Stop \(agentName) from starting when run #\(watchedProcessId) finishes"
	}

	var detailRecord: HomerRecordDetailReducer.Record {
		.continuation(self)
	}
}

extension HomerDispatch: HomerRecordPresentation {
	var chain: [HomerChainNode] {
		[
			HomerChainNode(caption: "Asked by", systemImage: "questionmark.bubble", name: originAgentName, processId: originProcessId),
			HomerChainNode(
				caption: status == .pending ? "Waits for" : "Question",
				systemImage: "text.bubble",
				name: status == .pending ? "Answer" : "Answered",
				processId: nil
			),
			HomerChainNode(
				caption: status == .dispatched ? "Started" : "Then starts",
				systemImage: "play.fill",
				name: agentName,
				processId: dispatchedProcessId
			),
		]
	}

	var sentence: String {
		"When the question run \(originProcessId) asked is answered, start \(agentName). Asked by \(originAgentName)."
	}

	var runs: [HomerRecordRun] {
		[HomerRecordRun(title: "Asking Run", systemImage: "questionmark.bubble", processId: originProcessId)]
			+ (dispatchedProcessId.map { [HomerRecordRun(title: "Started Run", systemImage: "play", processId: $0)] } ?? [])
	}

	var cancelHelp: String {
		"Expire the question so \(agentName) never starts"
	}

	var detailRecord: HomerRecordDetailReducer.Record {
		.dispatch(self)
	}
}

/// The record as a chain: the run that asked, what it waits for, and the agent it starts — with
/// the run that start made, once dispatched. Wraps on a narrow card.
struct HomerRecordChain<Record: HomerRecordPresentation>: View {
	let record: Record

	var body: some View {
		HomerFlowLayout(spacing: 8) {
			ForEach(Array(record.chain.enumerated()), id: \.offset) { index, node in
				if index > 0 {
					Image(systemName: "arrow.right")
						.scaledFont(.callout)
						.foregroundStyle(.tertiary)
						.padding(.vertical, 14)
				}
				VStack(alignment: .leading, spacing: 2) {
					Label(node.caption, systemImage: node.systemImage)
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
					Text(HomerRunLink.agentText(node.name, run: node.processId))
						.scaledFont(.callout)
						.lineLimit(1)
				}
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.homerInset()
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel(record.sentence)
	}
}

/// Run numbers as links inside a card's text, with a private scheme the card's `openURL` action
/// turns into `processTapped` — never opened as URLs.
enum HomerRunLink {
	/// "**starter** #7".
	static func agentText(_ name: String, run processId: Int?) -> AttributedString {
		var text = AttributedString(name)
		text.inlinePresentationIntent = .stronglyEmphasized
		if let processId {
			text += AttributedString(" ")
			var link = AttributedString("#\(processId)")
			link.link = processURL(processId)
			text += link
		}
		return text
	}

	nonisolated static func processURL(_ processId: Int) -> URL? {
		URL(string: "\(scheme):\(processId)")
	}

	nonisolated static func processId(from url: URL) -> Int? {
		guard url.scheme == scheme else {
			return nil
		}
		return Int(url.absoluteString.dropFirst(scheme.count + 1))
	}

	private nonisolated static let scheme = "homer-process"
}

/// "Created 07.10.26 18:52:55".
struct HomerRecordTimestamp: View {
	let title: String
	let epochSeconds: Double

	var body: some View {
		HStack(spacing: 4) {
			Text(title)
			Text(HomerFormat.timestamp(epochSeconds))
				.scaledFont(.caption, design: .monospaced)
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
	}
}

/// "Expires in 2h 5m", orange within the hour, ticking.
struct HomerExpiryLabel: View {
	let expiresAt: Double

	var body: some View {
		TimelineView(.periodic(from: .now, by: 30)) { context in
			let left = expiresAt - context.date.timeIntervalSince1970
			let isSoon = left <= HomerExpiry.soonWindow
			Label(
				left > 0 ? "Expires \(HomerFormat.timeUntil(expiresAt, now: context.date))" : "Expiring",
				systemImage: isSoon ? "clock.badge.exclamationmark" : "clock"
			)
			.scaledFont(.caption)
			.fontWeight(isSoon ? .medium : .regular)
			.foregroundStyle(isSoon ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
			.help("Given up on at \(HomerFormat.timestamp(expiresAt)) unless it starts first")
		}
	}
}

/// Why the record failed to start its agent.
struct HomerRecordFailure: View {
	let noun: String
	let error: String?

	var body: some View {
		Label {
			Text("\(noun.capitalized) failed: \(error ?? "")")
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)
		} icon: {
			Image(systemName: "exclamationmark.triangle.fill")
		}
		.scaledFont(.callout)
		.foregroundStyle(.red)
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerInset(tint: .red)
	}
}

/// A record's status as the console's colored badge shows it.
struct HomerRecordStatusBadge<Status: HomerDeferredStatus>: View {
	let status: Status

	var body: some View {
		HomerPill(status.title, color: color)
			.help("Status: \(status.title)")
	}

	private var color: Color {
		switch status {
		case .pending:
			.orange
		case .dispatched:
			.green
		case .failed:
			.red
		default:
			status.rawValue == "DISPATCHING" ? .blue : .gray
		}
	}
}
