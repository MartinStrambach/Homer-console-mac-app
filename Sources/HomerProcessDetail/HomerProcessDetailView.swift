import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import HomerWorkflowGraph
import SwiftUI

/// A run's page (`app/(dashboard)/processes/[id]/page.tsx`), in place of the page that opened
/// it: Back, its status and actions, runner, open questions, status timeline and executions,
/// each execution's output a click away. `backTitle` names that page — Back returns there once
/// no earlier run is left to go back to. The questions are the instance's — answered there, as
/// on the Questions page — so the instance's view supplies them: `questions` draws the given
/// run's as a `HomerDetailSection`, or nothing when it has none.
package struct HomerProcessDetailView<Questions: View>: View {
	@Bindable
	var store: StoreOf<HomerProcessDetailReducer>
	let backTitle: String
	@ViewBuilder
	let questions: (_ processId: Int) -> Questions

	/// The content's width, which decides between one column and two.
	@State
	private var contentWidth: CGFloat = 0

	package init(
		store: StoreOf<HomerProcessDetailReducer>,
		backTitle: String,
		@ViewBuilder questions: @escaping (_ processId: Int) -> Questions
	) {
		self.store = store
		self.backTitle = backTitle
		self.questions = questions
	}

	package var body: some View {
		VStack(spacing: 0) {
			navigationBar
			header
			Divider()
			if let error = store.loadError {
				HomerErrorBanner(message: error)
			}
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.sheet(item: $store.scope(\.$output, action: \.output)) { outputStore in
			HomerProcessOutputView(store: outputStore)
		}
		.sheet(item: $store.scope(\.$artifacts, action: \.artifacts)) { artifactsStore in
			HomerArtifactsView(store: artifactsStore)
		}
		.sheet(item: $store.webPage) { page in
			HomerWebPageView(page: page)
		}
		.alert($store.scope(\.$alert, action: \.alert))
	}

	// MARK: - Header

	/// Back goes to the run shown before this one, if any, else to the page that opened it.
	private var navigationBar: some View {
		HStack(spacing: 10) {
			let previous = store.backStack.last.map { "#\($0)" }
			Button {
				store.send(.backTapped)
			} label: {
				Label(previous ?? backTitle, systemImage: "chevron.left")
			}
			.buttonStyle(.scaledBordered)
			.keyboardShortcut("[", modifiers: .command)
			.help("Back to \(previous.map { "run \($0)" } ?? backTitle) (⌘[)")

			Spacer()

			Button {
				store.send(.openInWebConsoleTapped)
			} label: {
				Label("Web Console", systemImage: "safari")
			}
			.buttonStyle(.scaledBordered)
			.help("Open this run in the web console")
		}
		.scaledFont(.callout)
		.padding(.horizontal)
		.padding(.top, 8)
	}

	/// The run's icon, number and status, its agent and owner, and the actions.
	private var header: some View {
		HStack(alignment: .center, spacing: 14) {
			HomerIconTile(
				systemImage: store.process?.status.systemImage ?? "doc.text.magnifyingglass",
				color: store.process?.status.color ?? .gray,
				size: 44
			)

			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 8) {
					Text("Process #\(store.processId)")
						.scaledFont(.title2)
						.fontWeight(.bold)
						.textSelection(.enabled)
					if let process = store.process {
						HomerStatusBadge(status: process.status)
					}
					if store.process == nil, store.loadError == nil {
						ProgressView()
							.controlSize(.small)
					}
				}
				if let process = store.process {
					subtitle(process)
				}
			}

			Spacer(minLength: 12)

			HStack(spacing: 8) {
				actions
			}
		}
		.padding(.horizontal)
		.padding(.top, 10)
		.padding(.bottom, 14)
	}

	/// The agent and who started the run, then its tags and links.
	private func subtitle(_ process: HomerProcess) -> some View {
		HomerFlowLayout(spacing: 10) {
			HStack(spacing: 4) {
				Text(process.agentName)
					.fontWeight(.semibold)
					.textSelection(.enabled)
				if let owner = process.owner {
					Text("· by \(owner)")
						.foregroundStyle(.secondary)
				}
			}
			if let tags = process.tags, !tags.isEmpty {
				ForEach(tags, id: \.self) { tag in
					HomerChip(tag, monospaced: true)
				}
			}
			if let parent = process.parentProcessId {
				Button {
					store.send(.processLinkTapped(processId: parent))
				} label: {
					Label("Parent #\(parent)", systemImage: "arrow.turn.left.up")
				}
				.buttonStyle(.link)
			}
			if let trace = process.langfuseTraceUrl.flatMap(URL.init(string:)) {
				Link(destination: trace) {
					Label("Langfuse trace", systemImage: "arrow.up.right.square")
				}
			}
		}
		.scaledFont(.callout)
	}

	@ViewBuilder
	private var actions: some View {
		if store.actionInFlight != nil {
			ProgressView()
				.controlSize(.small)
		}
		if store.process != nil {
			Button {
				store.send(.browseArtifactsTapped)
			} label: {
				Label("Artifacts", systemImage: "doc.on.doc")
			}
			.buttonStyle(.scaledBordered)
			.help("Browse and download the run's artifacts")
		}
		if store.canRetry {
			Button {
				store.send(.retryTapped)
			} label: {
				Label("Retry", systemImage: "arrow.counterclockwise")
			}
			.buttonStyle(.scaledBordered)
			.disabled(store.actionInFlight != nil)
			.help("Start the run again with the same inputs")
		}
		if store.canResume {
			Button {
				store.send(.resumeTapped)
			} label: {
				Label("Resume", systemImage: "forward.end")
			}
			.buttonStyle(.scaledBordered)
			.disabled(store.actionInFlight != nil)
			.help("Start a new run from the workflow's last checkpoint")
		}
		if store.canKill {
			Button(role: .destructive) {
				store.send(.killTapped)
			} label: {
				Label("Kill Process", systemImage: "xmark.octagon")
					.foregroundStyle(.red)
			}
			.buttonStyle(.scaledBordered)
				.disabled(store.actionInFlight != nil)
		}
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		if let process = store.process {
			// A plain stack: a run has a handful of sections and executions.
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					stats(process)
					if contentWidth >= Self.twoColumnWidth {
						// The run's work beside its history and where it ran.
						HStack(alignment: .top, spacing: 16) {
							VStack(alignment: .leading, spacing: 16) {
								questions(store.processId)
								executions(process)
							}
							.frame(maxWidth: .infinity)
							VStack(alignment: .leading, spacing: 16) {
								timeline(process)
								if let runner = process.runner {
									HomerRunnerPanel(runner: runner)
								}
							}
							.frame(width: 340)
						}
					}
					else {
						if let runner = process.runner {
							HomerRunnerPanel(runner: runner)
						}
						questions(store.processId)
						timeline(process)
						executions(process)
					}
				}
				.padding()
				.frame(maxWidth: .infinity, alignment: .leading)
				.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
			}
		}
		else if store.loadError == nil {
			ProgressView("Loading process details…")
		}
		else {
			// The banner above says why; something still has to fill the page, or the stack
			// shrinks to its header and the window centres it.
			Color.clear
		}
	}

	/// From this wide on, the timeline and runner move to a column of their own.
	private static var twoColumnWidth: CGFloat {
		980
	}

	/// How long it ran, what it cost, its commands and when it started.
	private func stats(_ process: HomerProcess) -> some View {
		HomerStatGrid {
			HomerStat("Duration", systemImage: "timer") {
				if let start = process.history.first?.timestamp {
					if process.status.hasEnded, let end = process.history.last?.timestamp {
						Text(HomerFormat.duration(from: start, to: end))
							.monospacedDigit()
					}
					else {
						TimelineView(.periodic(from: .now, by: 1)) { context in
							Text(HomerFormat.duration(from: start, to: context.date.timeIntervalSince1970))
								.monospacedDigit()
						}
					}
				}
				else {
					Text(verbatim: "—")
				}
			}
			// From the cost ledger, not the output: still there once the artifacts are purged.
			HomerStat("Cost", systemImage: "dollarsign.circle") {
				if let cost = process.costUsd, cost > 0 {
					Text(HomerFormat.cost(cost))
						.monospacedDigit()
				}
				else {
					Text(verbatim: "—")
				}
			}
			HomerStat("Commands", systemImage: "terminal") {
				HStack(alignment: .firstTextBaseline, spacing: 6) {
					Text("\(process.executions.count + (process.currentCommand == nil ? 0 : 1))")
						.monospacedDigit()
					let failed = process.executions.filter { $0.skipped != true && $0.resultCode != 0 }.count
					if failed > 0 {
						Text("\(failed) failed")
							.scaledFont(.callout)
							.foregroundStyle(.red)
					}
					else if process.currentCommand != nil {
						Text("1 running")
							.scaledFont(.callout)
							.foregroundStyle(.blue)
					}
				}
			}
			HomerStat("Started", systemImage: "calendar") {
				if let start = process.history.first?.timestamp {
					let date = Date(timeIntervalSince1970: start)
					Text(date, format: .relative(presentation: .named))
						.help(HomerFormat.timestamp(start))
				}
				else {
					Text(verbatim: "—")
				}
			}
		}
	}

	/// The status changes as a connected timeline, how long each status lasted, and the
	/// workspace's purge still ahead.
	private func timeline(_ process: HomerProcess) -> some View {
		HomerDetailSection("Status Timeline", subtitle: "History of status changes", systemImage: "clock.arrow.circlepath") {
			VStack(alignment: .leading, spacing: 0) {
				let history = process.history
				ForEach(Array(history.enumerated()), id: \.offset) { index, entry in
					let next = index + 1 < history.count ? history[index + 1].timestamp : nil
					HomerTimelineStep(
						color: entry.status.color,
						isLast: index == history.count - 1 && process.purgeAt == nil
					) {
						HStack(alignment: .firstTextBaseline, spacing: 6) {
							Text(entry.status.title)
								.fontWeight(.semibold)
							if let next {
								Text(HomerFormat.duration(from: entry.timestamp, to: next))
									.scaledFont(.caption)
									.foregroundStyle(.secondary)
									.monospacedDigit()
							}
						}
						Text(HomerFormat.timestamp(entry.timestamp))
							.scaledFont(.caption, design: .monospaced)
							.foregroundStyle(.secondary)
					}
				}
				if let purgeAt = process.purgeAt {
					HomerTimelineStep(color: .secondary, isLast: true, isPending: true) {
						TimelineView(.periodic(from: .now, by: 30)) { context in
							Text("Workspace purge \(HomerFormat.timeUntil(purgeAt, now: context.date))")
								.foregroundStyle(.secondary)
						}
						Text(HomerFormat.timestamp(purgeAt))
							.scaledFont(.caption, design: .monospaced)
							.foregroundStyle(.secondary)
					}
				}
			}
			.scaledFont(.callout)
		}
	}

	private func executions(_ process: HomerProcess) -> some View {
		HomerDetailSection("Executions", subtitle: "Command execution history", systemImage: "terminal") {
			if process.executions.isEmpty, process.currentCommand == nil {
				Text("No executions yet")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
			else {
				VStack(spacing: 8) {
					ForEach(Array(process.executions.enumerated()), id: \.offset) { index, execution in
						HomerExecutionRow(
							store: store,
							index: index,
							execution: execution
						)
					}
					if let command = process.currentCommand {
						HomerCurrentCommandRow(
							store: store,
							command: command,
							commandStart: process.currentCommandStart,
							executionIndex: process.executions.count
						)
					}
				}
			}
		}
	}
}

// MARK: - Sections

/// One status of the timeline: a dot in its color on the line that joins it to the next. A
/// pending step — the purge still ahead — is a hollow dot.
private struct HomerTimelineStep<Content: View>: View {
	let color: Color
	let isLast: Bool
	var isPending = false
	@ViewBuilder
	let content: Content

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			Group {
				if isPending {
					Circle()
						.strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
				}
				else {
					Circle()
						.fill(color)
				}
			}
			.frame(width: 10, height: 10)
			.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

			VStack(alignment: .leading, spacing: 2) {
				content
			}
			.padding(.bottom, isLast ? 0 : 14)
		}
		// The line runs from under this dot to the next one, the row's whole height.
		.background(alignment: .topLeading) {
			if !isLast {
				Rectangle()
					.fill(Color(nsColor: .separatorColor))
					.frame(width: 2)
					.padding(.top, 14)
					.padding(.leading, 4)
			}
		}
	}
}

/// Where the run executes (`runner-panel.tsx`): the runner, its pod and phase, the pod's
/// timestamps and why it failed to start.
struct HomerRunnerPanel: View {
	let runner: HomerProcess.Runner

	@State
	private var showsStartupFailure = false

	var body: some View {
		HomerDetailSection("Runner", subtitle: "Execution backend for this process", systemImage: "server.rack") {
			VStack(alignment: .leading, spacing: 10) {
				Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
					HomerGridRow("Alias") {
						HStack(spacing: 8) {
							Text(runner.displayName)
								.scaledFont(.callout, design: .monospaced)
								.textSelection(.enabled)
							if let phase = runner.podPhase {
								HomerPill(Self.title(podPhase: phase), color: HomerRunnerView.color(podPhase: phase))
							}
						}
					}
					if let podName = runner.podName {
						HomerGridRow("Pod") {
							HStack(spacing: 6) {
								Text(podName)
									.scaledFont(.callout, design: .monospaced)
									.lineLimit(1)
									.truncationMode(.middle)
									.textSelection(.enabled)
								Button {
									NSPasteboard.general.clearContents()
									NSPasteboard.general.setString(podName, forType: .string)
								} label: {
									Image(systemName: "doc.on.doc")
								}
								.buttonStyle(.borderless)
								.help("Copy pod name")
							}
						}
					}
					ForEach(times, id: \.0) { name, time in
						HomerGridRow(name) {
							Text(HomerFormat.timestamp(time))
								.scaledFont(.callout, design: .monospaced)
						}
					}
				}
				if let failure = runner.startupFailure {
					DisclosureGroup(isExpanded: $showsStartupFailure) {
						VStack(alignment: .leading, spacing: 6) {
							Text(failure.message)
								.foregroundStyle(.red)
							ForEach(Array(failure.events.enumerated()), id: \.offset) { _, event in
								Text("• " + event)
									.scaledFont(.caption, design: .monospaced)
									.foregroundStyle(.secondary)
							}
						}
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.top, 4)
					} label: {
						Text("Startup failure: \(failure.reason)")
							.fontWeight(.medium)
							.foregroundStyle(.red)
					}
					.padding(10)
					.homerInset(tint: .red)
				}
			}
			.scaledFont(.callout)
		}
	}

	private var times: [(String, Double)] {
		[("Created", runner.createdAt), ("Ready", runner.readyAt), ("Ended", runner.endedAt)]
			.compactMap { name, time in time.map { (name, $0) } }
	}

	static func title(podPhase: String) -> String {
		podPhase == "KEPT_FOR_DEBUG" ? "Kept for debug" : podPhase.capitalized
	}
}

// MARK: - Executions

/// A finished command (`execution-item.tsx`): its outcome and duration, opened to its times,
/// output files, error and — for the command that ran the workflow — the workflow's state.
struct HomerExecutionRow: View {
	let store: StoreOf<HomerProcessDetailReducer>
	let index: Int
	let execution: HomerProcess.Execution

	private var isExpanded: Bool {
		store.expandedExecutions.contains(index)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Button {
				store.send(.executionToggled(index: index))
			} label: {
				HStack(spacing: 10) {
					Image(systemName: "chevron.right")
						.scaledFont(.caption)
						.fontWeight(.semibold)
						.foregroundStyle(.secondary)
						.rotationEffect(.degrees(isExpanded ? 90 : 0))
						.frame(width: 12)
					Text("\(index + 1)")
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.secondary)
						.frame(minWidth: 16, alignment: .trailing)
					outcomeIcon
					Text(execution.label)
						.scaledFont(.body)
						.fontWeight(.medium)
					outcomeLabel
					Spacer()
					if let start = execution.start, let end = execution.end {
						Label(HomerFormat.duration(from: start, to: end), systemImage: "timer")
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
							.monospacedDigit()
					}
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.contentShape(Rectangle())
			}
			.buttonStyle(.homerRow)
			.animation(.snappy(duration: 0.2), value: isExpanded)

			if isExpanded {
				Divider()
				details
					.padding(12)
			}
		}
		.homerInset()
	}

	/// The outcome as a symbol on a tint of its color.
	private var outcomeIcon: some View {
		let (symbol, color): (String, Color) = if execution.skipped == true {
			("minus", .secondary)
		}
		else if execution.resultCode == 0 {
			("checkmark", .green)
		}
		else {
			("xmark", .red)
		}
		return Image(systemName: symbol)
			.font(.system(size: 9, weight: .bold))
			.foregroundStyle(color)
			.frame(width: 18, height: 18)
			.background(color.opacity(0.15), in: Circle())
	}

	/// Only what the icon does not say: a skip, or a failure's exit code.
	@ViewBuilder
	private var outcomeLabel: some View {
		if execution.skipped == true {
			HomerPill("Skipped", color: .gray)
				.help(execution.errMsg ?? "")
		}
		else if execution.resultCode != 0 {
			HomerPill("Exit code \(execution.resultCode)", color: .red)
		}
		else {
			Text("Exit code: 0")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
		}
	}

	private var details: some View {
		VStack(alignment: .leading, spacing: 10) {
			Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
				if let start = execution.start {
					HomerGridRow("Start") { timestamp(start) }
				}
				if let end = execution.end {
					HomerGridRow("End") { timestamp(end) }
				}
				HomerGridRow("Stdout") { outputLinks(execution.stdOut, stream: .stdout) }
				HomerGridRow("Stderr") { outputLinks(execution.stdErr, stream: .stderr) }
				if let error = execution.errMsg {
					HomerGridRow("Error") {
						Text(error)
							.foregroundStyle(.red)
							.textSelection(.enabled)
					}
				}
			}
			if execution.label == store.langGraphLabel {
				VStack(alignment: .leading, spacing: 6) {
					Text("Workflow:")
						.fontWeight(.medium)
					HomerWorkflowSlot(store: store)
				}
				.padding(.top, 4)
			}
		}
		.scaledFont(.callout)
	}

	private func timestamp(_ time: Double) -> some View {
		Text(HomerFormat.timestamp(time))
			.scaledFont(.callout, design: .monospaced)
			.foregroundStyle(.secondary)
	}

	@ViewBuilder
	private func outputLinks(_ path: String?, stream: HomerOutputStream) -> some View {
		if let path {
			HStack(spacing: 6) {
				Button {
					store.send(.viewOutputTapped(executionIndex: index, stream: stream))
				} label: {
					Label("View", systemImage: "eye")
				}
				.buttonStyle(.link)
				Text("|")
					.foregroundStyle(.secondary)
				Button {
					store.send(.downloadTapped(path: path))
				} label: {
					Label(HomerArtifactPath.fileName(path), systemImage: "arrow.down.circle")
						.scaledFont(.callout, design: .monospaced)
				}
				.buttonStyle(.link)
				.disabled(store.downloadingPaths.contains(path))
				.help("Save to Downloads")
				if store.downloadingPaths.contains(path) {
					ProgressView()
						.controlSize(.mini)
				}
			}
		}
		else {
			Text("-")
				.foregroundStyle(.secondary)
		}
	}
}

/// The command running now (`current-command-box.tsx`): its live output, how long it has run,
/// and — when it runs the workflow — the workflow's state under it.
struct HomerCurrentCommandRow: View {
	let store: StoreOf<HomerProcessDetailReducer>
	let command: String
	let commandStart: Double?
	let executionIndex: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				ProgressView()
					.controlSize(.small)
				Text(command)
					.scaledFont(.body)
					.fontWeight(.medium)
				Text("Running…")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
				Button {
					store.send(.viewOutputTapped(executionIndex: executionIndex, stream: .stdout))
				} label: {
					Label("View live output", systemImage: "eye")
				}
				.buttonStyle(.link)
				.scaledFont(.callout)
				if store.liveCommandIsWorkflow {
					Button {
						store.send(.liveWorkflowToggled)
					} label: {
						Label(
							store.isLiveWorkflowExpanded ? "Hide workflow" : "Show workflow",
							systemImage: "point.3.connected.trianglepath.dotted"
						)
					}
					.buttonStyle(.link)
					.scaledFont(.callout)
				}
				Spacer()
				if let commandStart {
					VStack(alignment: .trailing, spacing: 2) {
						Text(HomerFormat.timestamp(commandStart))
						TimelineView(.periodic(from: .now, by: 1)) { context in
							Text(HomerFormat.duration(from: commandStart, to: context.date.timeIntervalSince1970))
								.monospacedDigit()
						}
					}
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
				}
			}
			if store.isLiveWorkflowExpanded, store.liveCommandIsWorkflow {
				Divider()
				HomerWorkflowSlot(store: store)
			}
		}
		.padding(12)
		.homerInset(tint: .blue)
		.overlay {
			RoundedRectangle(cornerRadius: HomerRadius.inset, style: .continuous)
				.strokeBorder(Color.blue.opacity(0.3))
		}
	}
}

/// The workflow's state where it is shown, or that it is loading.
struct HomerWorkflowSlot: View {
	let store: StoreOf<HomerProcessDetailReducer>

	var body: some View {
		if let workflow = store.workflow {
			HomerWorkflowStatusView(
				status: workflow,
				imageName: "Run \(store.processId) \(workflow.label) workflow",
				openProcess: { store.send(.processLinkTapped(processId: $0)) },
				openGraph: { store.send(.openInWebConsoleTapped) }
			)
		}
		else {
			HStack(spacing: 6) {
				ProgressView()
					.controlSize(.small)
				Text("Loading workflow status…")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}
}
