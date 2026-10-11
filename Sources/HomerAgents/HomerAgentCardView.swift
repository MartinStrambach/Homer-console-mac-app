import AppKit
import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// One agent as the console's card shows it (`components/agents/agent-card.tsx`): name,
/// "Scheduled", description, Edit and Run, the script count, the cron with its next and last
/// run, and the declared parameters — as chips, each one's details in its tooltip; the agent's
/// page lists them in full.
struct HomerAgentCard: View {
	let agent: HomerAgent
	let user: HomerUser
	let store: StoreOf<HomerAgentsReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			header

			HStack(spacing: 14) {
				Label("\(agent.scriptCount) \(agent.scriptCount == 1 ? "script" : "scripts")", systemImage: "terminal")
				Label(
					agent.inputs.isEmpty
						? "No parameters"
						: "\(agent.inputs.count) \(agent.inputs.count == 1 ? "parameter" : "parameters")",
					systemImage: "slider.horizontal.3"
				)
			}
			.scaledFont(.callout)
			.foregroundStyle(.secondary)

			if let cron = agent.cron {
				cronBlock(cron)
			}

			parameters
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .topLeading)
		.homerHoverCard()
		.contentShape(RoundedRectangle(cornerRadius: HomerRadius.card, style: .continuous))
		.contextMenu {
			contextMenu
		}
	}

	private var header: some View {
		HStack(alignment: .top, spacing: 10) {
			HomerIconTile(
				systemImage: agent.cron == nil ? "square.stack.3d.up.fill" : "calendar.badge.clock",
				color: agent.cron == nil ? .accentColor : .purple,
				size: 30
			)

			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 8) {
					Button {
						store.send(.agentTapped(agentName: agent.name))
					} label: {
						Text(agent.name)
							.scaledFont(.title3)
							.fontWeight(.semibold)
							.multilineTextAlignment(.leading)
					}
					.buttonStyle(.link)
					.help("Open the agent: its parameters, workflow graph and run history")

					if agent.cron != nil {
						HomerPill("Scheduled", color: .purple, systemImage: "clock")
					}
				}
				if let description = agent.description, !description.isEmpty {
					Text(description)
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}

			Spacer(minLength: 0)

			Button {
				store.send(.workflowGraphTapped(agentName: agent.name))
			} label: {
				Image(systemName: "point.3.connected.trianglepath.dotted")
			}
			.buttonStyle(.borderless)
			.help("Show the workflow graph of \(agent.name)'s LangGraph commands")

			if user.canEdit(agent) {
				Button {
					store.send(.editTapped(agentName: agent.name))
				} label: {
					Image(systemName: "pencil")
				}
				.buttonStyle(.borderless)
				.help("Edit agent \(agent.name)")
			}
			if user.canRun(agent) {
				Button {
					store.send(.runTapped(agentName: agent.name))
				} label: {
					Image(systemName: "play.fill")
				}
				.buttonStyle(.borderless)
				.help("Run agent \(agent.name)")
			}
		}
	}

	private func cronBlock(_ cron: HomerAgent.Cron) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Label {
				HStack(spacing: 4) {
					Text(cron.expression)
						.scaledFont(.caption, design: .monospaced)
						.foregroundStyle(.primary)
						.textSelection(.enabled)
					if !cron.timezone.isEmpty {
						Text("(\(cron.timezone))")
					}
				}
			} icon: {
				Image(systemName: "clock")
					.foregroundStyle(.purple)
			}
			.scaledFont(.caption)
			if let nextRunAt = cron.nextRunAt {
				Label {
					HStack(spacing: 4) {
						Text("Next")
						HomerScheduleCountdownText(epochSeconds: nextRunAt)
					}
				} icon: {
					Image(systemName: "calendar")
				}
				.scaledFont(.caption)
				.help(HomerFormat.timestamp(nextRunAt))
			}
			if let lastRunAt = cron.lastRunAt {
				Label {
					HStack(spacing: 4) {
						Text("Last")
						if let processId = cron.lastRunProcessId {
							Button(HomerFormat.timestamp(lastRunAt)) {
								store.send(.processTapped(processId: processId))
							}
							.buttonStyle(.link)
							.help("Open process \(processId)")
						}
						else {
							Text(HomerFormat.timestamp(lastRunAt))
						}
					}
				} icon: {
					Image(systemName: "clock.arrow.circlepath")
				}
				.scaledFont(.caption)
			}
		}
		.foregroundStyle(.secondary)
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerInset(tint: .purple)
	}

	/// The parameters as chips — a required one marked — with type, variable and transformer
	/// in the tooltip.
	@ViewBuilder
	private var parameters: some View {
		if !agent.inputs.isEmpty {
			HomerFlowLayout(spacing: 6) {
				ForEach(agent.inputs) { input in
					HStack(spacing: 4) {
						Text(input.paramName)
							.scaledFont(.caption, design: .monospaced)
						if input.required {
							Circle()
								.fill(.red)
								.frame(width: 5, height: 5)
								.accessibilityLabel("required")
						}
					}
					.padding(.horizontal, 8)
					.padding(.vertical, 3)
					.background(.fill.tertiary, in: Capsule())
					.help(
						"\(input.type)\(input.required ? ", required" : "") · Env: \(input.envName) · \(input.transformer.summary)"
					)
				}
			}
		}
	}

	@ViewBuilder
	private var contextMenu: some View {
		Button {
			store.send(.agentTapped(agentName: agent.name))
		} label: {
			Label("Open Agent", systemImage: "square.stack.3d.up")
		}
		Button {
			store.send(.workflowGraphTapped(agentName: agent.name))
		} label: {
			Label("Show Workflow Graph", systemImage: "point.3.connected.trianglepath.dotted")
		}
		if let url = HomerEndpoint.pageURL(baseURL: store.baseURL, path: agent.consolePath) {
			Button {
				NSWorkspace.shared.open(url)
			} label: {
				Label("Open in Browser", systemImage: "safari")
			}
		}
		if user.canRun(agent) || user.canEdit(agent) {
			Divider()
		}
		if user.canRun(agent) {
			Button {
				store.send(.runTapped(agentName: agent.name))
			} label: {
				Label("Run…", systemImage: "play")
			}
		}
		if user.canEdit(agent) {
			Button {
				store.send(.editTapped(agentName: agent.name))
			} label: {
				Label("Edit Agent", systemImage: "pencil")
			}
		}
		if let processId = agent.cron?.lastRunProcessId {
			Button {
				store.send(.processTapped(processId: processId))
			} label: {
				Label("Open Last Scheduled Run #\(processId)", systemImage: "doc.text.magnifyingglass")
			}
		}
		Divider()
		Button {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(agent.name, forType: .string)
		} label: {
			Label("Copy Agent Name", systemImage: "doc.on.doc")
		}
	}
}

/// A declared input: name, type, "required", its environment variable and transformer — on the
/// card and above its field in the Run sheet.
struct HomerAgentInputHeader: View {
	let input: HomerAgent.Input

	var body: some View {
		HStack(spacing: 6) {
			Text(input.paramName)
				.scaledFont(.callout, design: .monospaced)
			HomerAgentBadge(text: input.type)
			if input.required {
				HomerAgentBadge(text: "required", tint: .red)
			}
		}
	}
}

struct HomerAgentInputDetails: View {
	let input: HomerAgent.Input

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			Text("Env: \(input.envName)")
			Text(input.transformer.summary)
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
		.textSelection(.enabled)
	}
}

struct HomerAgentBadge: View {
	let text: String
	/// Nil for a neutral badge.
	var tint: Color?

	var body: some View {
		Text(text)
			.scaledFont(.caption2)
			.fontWeight(.medium)
			.foregroundStyle(tint ?? Color.primary)
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background((tint ?? Color.secondary).opacity(0.15), in: Capsule())
	}
}

/// What a reload changed (the console's banner under the search): green, or amber when some
/// agent failed to load.
struct HomerAgentReloadBanner: View {
	let result: HomerAgentReloadResult
	let onDismiss: () -> Void

	var body: some View {
		HomerAgentDismissableBanner(tint: result.errors.isEmpty ? .green : .orange, onDismiss: onDismiss) {
			VStack(alignment: .leading, spacing: 4) {
				Text(
					"Reloaded — \(result.added.count) added · \(result.updated.count) updated · \(result.removed.count) removed"
				)
				.fontWeight(.medium)
				if !result.added.isEmpty {
					changes("Added:", result.added, color: .green)
				}
				if !result.updated.isEmpty {
					changes("Updated:", result.updated, color: .blue)
				}
				if !result.removed.isEmpty {
					changes("Removed:", result.removed, color: .secondary)
				}
				ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
					Text(error)
						.foregroundStyle(.red)
						.textSelection(.enabled)
				}
			}
		}
	}

	private func changes(_ title: String, _ names: [String], color: Color) -> some View {
		let title = Text(title).foregroundStyle(color).fontWeight(.medium)
		return Text("\(title) \(names.joined(separator: ", "))")
			.textSelection(.enabled)
	}
}

/// A banner under the toolbar with a close button, on a tint of its color.
struct HomerAgentDismissableBanner<Content: View>: View {
	let tint: Color
	let onDismiss: () -> Void
	let content: Content

	init(tint: Color, onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
		self.tint = tint
		self.onDismiss = onDismiss
		self.content = content()
	}

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			content
				.frame(maxWidth: .infinity, alignment: .leading)
			Button(action: onDismiss) {
				Image(systemName: "xmark")
					.fontWeight(.semibold)
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.help("Dismiss")
		}
		.scaledFont(.callout)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.homerInset(tint: tint)
		.overlay {
			RoundedRectangle(cornerRadius: HomerRadius.inset, style: .continuous)
				.strokeBorder(tint.opacity(0.25))
		}
		.padding(.horizontal)
		.padding(.vertical, 6)
	}
}
