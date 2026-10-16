import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The runs around the one on the page (`RelatedRuns` in `page.tsx`, ADR-0058): a flow root's
/// whole flow (`flow-section.tsx`) — every visible run below it, oldest first, the root agent's
/// own resume segments behind a toggle — or any other run's direct children
/// (`child-runs-card.tsx`). Each run opens on this page, with Back. Nothing until the list is
/// read, and nothing for a run with no runs under it: most runs are alone.
struct HomerRelatedRunsSection: View {
	let store: StoreOf<HomerProcessDetailReducer>

	var body: some View {
		if let page = store.relatedRuns, page.total > 0 {
			if store.isFlowRoot {
				flow(page)
			}
			else {
				children(page)
			}
		}
	}

	private func flow(_ page: HomerProcessPage) -> some View {
		HomerDetailSection("Flow", subtitle: "Every run below this one, oldest first", systemImage: "arrow.triangle.branch") {
			VStack(alignment: .leading, spacing: 10) {
				let runs = store.visibleFlowRuns
				if runs.isEmpty {
					Text("Only resume segments of this run")
						.foregroundStyle(.secondary)
				}
				else {
					rows(runs) { run in
						if let cost = run.costUsd, cost > 0 {
							Text(HomerFormat.cost(cost))
								.scaledFont(.callout, design: .monospaced)
								.foregroundStyle(.secondary)
						}
						Text("parent \(run.parentProcessId.map { "#\($0)" } ?? "—")")
							.scaledFont(.caption, design: .monospaced)
							.foregroundStyle(.secondary)
					}
				}
				HStack(spacing: 12) {
					Text(Self.count(page, noun: "in this flow"))
						.foregroundStyle(.secondary)
						.monospacedDigit()
					Spacer()
					if store.hasResumeSegments {
						Button {
							store.send(.resumeSegmentsToggled)
						} label: {
							Label(
								store.showsResumeSegments ? "Hide resume segments" : "Show resume segments",
								systemImage: store.showsResumeSegments ? "eye.slash" : "eye"
							)
						}
						.buttonStyle(.scaledBordered)
						.controlSize(.small)
						.help("The root agent's own runs: the segments a resume of it starts")
					}
				}
			}
			.scaledFont(.callout)
		}
	}

	private func children(_ page: HomerProcessPage) -> some View {
		HomerDetailSection("Child Runs", subtitle: "Runs started by this process", systemImage: "arrow.turn.down.right") {
			VStack(alignment: .leading, spacing: 10) {
				rows(page.processes) { run in
					if let tags = run.tags, !tags.isEmpty {
						ForEach(tags, id: \.self) { tag in
							HomerChip(tag, monospaced: true)
						}
					}
				}
				if page.total > page.processes.count {
					Text(Self.count(page, noun: "started by this process"))
						.foregroundStyle(.secondary)
						.monospacedDigit()
				}
			}
			.scaledFont(.callout)
		}
	}

	/// One line per run: its number, agent and status, an open question, then what the list
	/// adds.
	private func rows<Extra: View>(_ runs: [HomerProcess], @ViewBuilder extra: @escaping (HomerProcess) -> Extra) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(runs) { run in
				HomerFlowLayout(spacing: 10) {
					Button {
						store.send(.processLinkTapped(processId: run.id))
					} label: {
						Text("#\(run.id)")
							.scaledFont(.callout, design: .monospaced)
					}
					.buttonStyle(.link)
					.help("Open run #\(run.id)")
					Text(run.agentName)
						.fontWeight(.medium)
						.textSelection(.enabled)
					HomerStatusBadge(status: run.status)
					HomerQuestionCountBadge(count: run.openQuestions ?? 0)
					extra(run)
				}
			}
		}
	}

	/// "12 runs in this flow", with how many are listed when the read was cut.
	private static func count(_ page: HomerProcessPage, noun: String) -> String {
		var text = "\(page.total) \(page.total == 1 ? "run" : "runs") \(noun)"
		if page.total > page.processes.count {
			text += " (first \(page.processes.count) shown)"
		}
		return text
	}
}
