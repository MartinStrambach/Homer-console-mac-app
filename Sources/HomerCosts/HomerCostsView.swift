import ComposableArchitecture
import HomerCore
import HomerUI
import SwiftUI

/// The console's Costs page (`app/(dashboard)/costs/page.tsx`, `components/costs/*`): the
/// global spend of the last minute and each agent's of the last day against their caps, then the
/// ledger's per-agent spend for a month and of all time.
package struct HomerCostsView: View {
	let store: StoreOf<HomerCostsReducer>

	/// The content's width, which decides whether the two ledgers sit side by side.
	@State
	private var contentWidth: CGFloat = 0

	package init(store: StoreOf<HomerCostsReducer>) {
		self.store = store
	}

	package var body: some View {
		VStack(spacing: 0) {
			ForEach(store.errorMessages, id: \.self) { message in
				HomerErrorBanner(message: message)
			}
			if store.isLoading {
				ProgressView("Loading costs…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			else {
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						Text("Rolling-window Claude spend against configured caps, plus persistent monthly and all-time statistics.")
							.scaledFont(.callout)
							.foregroundStyle(.secondary)
						stats
						globalSpend
						perAgentSpend
						if contentWidth >= Self.sideBySideWidth {
							HStack(alignment: .top, spacing: 16) {
								monthlyCosts
								totalCosts
							}
						}
						else {
							monthlyCosts
							totalCosts
						}
					}
					.padding()
					.frame(maxWidth: 1100, alignment: .leading)
					.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
					.frame(maxWidth: .infinity)
				}
			}
		}
	}

	/// From this wide on, the month's and all-time ledgers sit side by side.
	private static let sideBySideWidth: CGFloat = 900

	// MARK: - Figures

	/// The page at a glance: the last minute against its cap, the last day, the shown month and
	/// all time.
	private var stats: some View {
		HomerStatGrid {
			HomerStat("Last 60 s", systemImage: "gauge.with.needle") {
				if let snapshot = store.snapshot {
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(HomerFormat.cost(snapshot.globalUsdLast60s))
							.monospacedDigit()
						if let cap = snapshot.globalCapUsdPerMin {
							let usage = HomerCostUsage(spentUsd: snapshot.globalUsdLast60s, capUsd: cap)
							Text(usage.percentText)
								.scaledFont(.callout)
								.foregroundStyle(HomerCostUsageBar.textColor(usage.level))
						}
					}
				}
				else {
					Text(verbatim: "—")
				}
			}
			HomerStat("Last 24 h", systemImage: "clock.arrow.circlepath") {
				Text(store.snapshot.map { HomerFormat.cost($0.perAgentUsdLast24h.values.reduce(0, +)) } ?? "—")
					.monospacedDigit()
			}
			HomerStat(store.shownMonth.map { HomerFormat.month($0) } ?? "This month", systemImage: "calendar") {
				Text(store.monthly.map { HomerFormat.cost($0.totalUsd) } ?? "—")
					.monospacedDigit()
			}
			HomerStat("All time", systemImage: "sum") {
				Text(store.totals.map { HomerFormat.cost($0.totalUsd) } ?? "—")
					.monospacedDigit()
			}
		}
	}

	// MARK: - Rolling windows

	private var globalSpend: some View {
		HomerCostCard("Global spend (last 60 s)") {
			if let snapshot = store.snapshot {
				if let takenAt = snapshot.snapshotAtSec {
					Text("As of \(HomerFormat.timestamp(takenAt))")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
			}
		} content: {
			if let snapshot = store.snapshot {
				HomerCostUsageBar(
					spentUsd: snapshot.globalUsdLast60s,
					capUsd: snapshot.globalCapUsdPerMin,
					label: "Global spend per minute"
				)
				.padding(.top, 2)
			}
			else {
				HomerCostPlaceholder(failed: store.snapshotError != nil)
			}
		}
	}

	private var perAgentSpend: some View {
		HomerCostCard("Per-agent spend (last 24 h)") {
			if let snapshot = store.snapshot {
				let usages = Self.byNearestCap(snapshot.agentUsages)
				if usages.isEmpty {
					HomerCostEmptyText("No agent spend recorded yet.")
				}
				else {
					Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
						GridRow {
							Text("Agent")
							Text("Spent (last 24 h)")
								.gridColumnAlignment(.trailing)
							Text("Cap")
								.gridColumnAlignment(.trailing)
							Text("Usage")
						}
						.scaledFont(.caption)
						.fontWeight(.medium)
						.foregroundStyle(.secondary)
						Divider()
						ForEach(usages) { usage in
							GridRow {
								Text(usage.agentName)
									.fontWeight(.medium)
									.lineLimit(1)
									.textSelection(.enabled)
								HomerCostAmount(usage.spentUsd)
								Group {
									if let cap = usage.capUsd {
										HomerCostAmount(cap)
									}
									else {
										Text(verbatim: "—")
									}
								}
								.foregroundStyle(.secondary)
								HomerCostUsageBar(
									spentUsd: usage.spentUsd,
									capUsd: usage.capUsd,
									label: "\(usage.agentName) spend per day",
									compact: true
								)
								.frame(minWidth: 180, maxWidth: .infinity)
							}
						}
					}
				}
			}
			else {
				HomerCostPlaceholder(failed: store.snapshotError != nil)
			}
		}
	}

	/// The agents nearest their cap first, then the uncapped ones by spend: what needs a look
	/// comes first.
	static func byNearestCap(_ usages: [HomerCostSnapshot.AgentUsage]) -> [HomerCostSnapshot.AgentUsage] {
		usages.sorted { lhs, rhs in
			switch (lhs.capUsd, rhs.capUsd) {
			case let (lhsCap?, rhsCap?):
				let lhsRatio = HomerCostUsage(spentUsd: lhs.spentUsd, capUsd: lhsCap).ratio
				let rhsRatio = HomerCostUsage(spentUsd: rhs.spentUsd, capUsd: rhsCap).ratio
				return lhsRatio != rhsRatio ? lhsRatio > rhsRatio : lhs.agentName < rhs.agentName
			case (.some, nil):
				return true
			case (nil, .some):
				return false
			case (nil, nil):
				return lhs.spentUsd != rhs.spentUsd ? lhs.spentUsd > rhs.spentUsd : lhs.agentName < rhs.agentName
			}
		}
	}

	// MARK: - Ledger

	private var monthlyCosts: some View {
		HomerCostCard("Monthly costs per agent (UTC)") {
			HStack(spacing: 8) {
				if store.monthly != nil, !store.isMonthlyCurrent, store.monthlyError == nil {
					ProgressView()
						.controlSize(.small)
				}
				Picker("Month", selection: Binding(
					get: { store.shownMonth ?? "" },
					set: { store.send(.monthSelected($0)) }
				)) {
					if store.monthChoices.isEmpty {
						Text(verbatim: "—").tag("")
					}
					ForEach(store.monthChoices, id: \.self) { month in
						Text(HomerFormat.month(month)).tag(month)
					}
				}
				.labelsHidden()
				.fixedSize()
				.disabled(store.monthly == nil)
				.help("Select month")
			}
		} content: {
			if let monthly = store.monthly {
				HomerCostLedgerTable(
					rows: monthly.rows,
					totalUsd: monthly.totalUsd,
					emptyText: "No costs recorded for this month."
				)
				// The previous month stays until the picked one answers, as in the console.
				.opacity(store.isMonthlyCurrent ? 1 : 0.5)
			}
			else {
				HomerCostPlaceholder(failed: store.monthlyError != nil)
			}
		}
	}

	private var totalCosts: some View {
		HomerCostCard("All-time costs per agent") {
			if let totals = store.totals {
				HomerCostLedgerTable(rows: totals.rows, totalUsd: totals.totalUsd, emptyText: "No costs recorded yet.")
			}
			else {
				HomerCostPlaceholder(failed: store.totalsError != nil)
			}
		}
	}
}

// MARK: - Pieces

/// A section of the page, drawn like the questions' cards: a title, an optional accessory at its
/// trailing edge, the content below.
private struct HomerCostCard<Accessory: View, Content: View>: View {
	let title: String
	let accessory: Accessory
	let content: Content

	init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
		self.title = title
		self.accessory = accessory()
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline) {
				Text(title)
					.scaledFont(.headline)
				Spacer(minLength: 8)
				accessory
			}
			content
				.scaledFont(.body)
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.homerCard()
	}
}

private extension HomerCostCard where Accessory == EmptyView {
	init(_ title: String, @ViewBuilder content: () -> Content) {
		self.init(title, accessory: { EmptyView() }, content: content)
	}
}

/// A USD amount in the console's `$0.0000`, digits aligned.
private struct HomerCostAmount: View {
	let usd: Double

	init(_ usd: Double) {
		self.usd = usd
	}

	var body: some View {
		Text(HomerFormat.cost(usd))
			.scaledFont(.body, design: .monospaced)
			.textSelection(.enabled)
	}
}

private struct HomerCostEmptyText: View {
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

/// A card whose data has not arrived: a spinner, or a dash once its call failed (the banner above
/// says why).
private struct HomerCostPlaceholder: View {
	let failed: Bool

	var body: some View {
		if failed {
			HomerCostEmptyText("Not available.")
		}
		else {
			ProgressView()
				.controlSize(.small)
		}
	}
}

/// The console's `CostUsageBar`: spend against a cap, the bar green, yellow from 80 % and red at
/// the cap. Without a cap there is no bar, only the spend. `compact` (a table row) leaves the
/// amounts to the row's own columns and puts the percentage under the bar.
struct HomerCostUsageBar: View {
	let spentUsd: Double
	let capUsd: Double?
	let label: String
	var compact = false

	var body: some View {
		if let capUsd {
			let usage = HomerCostUsage(spentUsd: spentUsd, capUsd: capUsd)
			VStack(alignment: .leading, spacing: compact ? 2 : 4) {
				if !compact {
					HStack(alignment: .firstTextBaseline) {
						Text(verbatim: "\(HomerFormat.cost(spentUsd)) / \(HomerFormat.cost(capUsd))")
							.scaledFont(.body, design: .monospaced)
							.textSelection(.enabled)
						Spacer(minLength: 8)
						Text(usage.level == .overCap ? "\(usage.percentText) — cap exceeded" : usage.percentText)
							.scaledFont(.caption)
							.fontWeight(.medium)
							.foregroundStyle(Self.textColor(usage.level))
					}
				}
				HStack(spacing: 8) {
					HomerCostBar(
						fraction: usage.percent / 100,
						color: barColor(usage.level),
						height: compact ? 6 : 10,
						marker: compact ? nil : Self.nearCapRatio
					)
					.accessibilityElement()
					.accessibilityLabel(label)
					.accessibilityValue(usage.percentText)
					if compact {
						Text(usage.percentText)
							.scaledFont(.caption)
							.fontWeight(usage.level == .normal ? .regular : .semibold)
							.foregroundStyle(Self.textColor(usage.level))
							.monospacedDigit()
							.frame(minWidth: 34, alignment: .trailing)
					}
				}
			}
		}
		else if compact {
			Text("No cap")
				.scaledFont(.caption)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		else {
			HStack(alignment: .firstTextBaseline) {
				Text(HomerFormat.cost(spentUsd))
					.scaledFont(.body, design: .monospaced)
					.textSelection(.enabled)
				Spacer(minLength: 8)
				Text("no cap configured")
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func barColor(_ level: HomerCostUsage.Level) -> Color {
		switch level {
		case .normal:
			.green
		case .nearCap:
			.yellow
		case .overCap:
			.red
		}
	}

	/// Where the bar turns yellow, marked on the large bars.
	private static let nearCapRatio = 0.8

	/// Orange rather than the bar's yellow: yellow text is unreadable on a light background.
	static func textColor(_ level: HomerCostUsage.Level) -> Color {
		switch level {
		case .normal:
			.secondary
		case .nearCap:
			.orange
		case .overCap:
			.red
		}
	}
}

/// A filled capsule: spend against a cap, or an agent's share of a ledger. `marker` ticks a
/// fraction of the track — where a usage bar turns yellow.
private struct HomerCostBar: View {
	let fraction: Double
	let color: Color
	var height: CGFloat = 8
	var marker: Double?

	var body: some View {
		Capsule()
			.fill(.quaternary)
			.frame(height: height)
			.overlay(alignment: .leading) {
				GeometryReader { proxy in
					Capsule()
						.fill(color.gradient)
						.frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
				}
			}
			.clipShape(Capsule())
			.overlay(alignment: .leading) {
				if let marker {
					GeometryReader { proxy in
						Rectangle()
							.fill(Color.primary.opacity(0.35))
							.frame(width: 1.5, height: height + 6)
							.offset(x: proxy.size.width * marker - 0.75, y: -3)
					}
					.frame(height: height)
					.help("\(Int(marker * 100))% of the cap: the bar turns yellow")
				}
			}
			.animation(.default, value: fraction)
	}
}

/// A ledger's per-agent spend with a total row, as `MonthlyCostsCard`/`TotalCostsCard` show it —
/// the biggest spender first, each row with its share of the total as a bar.
private struct HomerCostLedgerTable: View {
	let rows: [HomerAgentCost]
	let totalUsd: Double
	let emptyText: String

	var body: some View {
		if rows.isEmpty {
			HomerCostEmptyText(emptyText)
		}
		else {
			let sorted = rows.sorted { $0.usd != $1.usd ? $0.usd > $1.usd : $0.agentName < $1.agentName }
			VStack(alignment: .leading, spacing: 10) {
				ForEach(sorted) { row in
					let share = totalUsd > 0 ? row.usd / totalUsd : 0
					VStack(alignment: .leading, spacing: 4) {
						HStack(alignment: .firstTextBaseline, spacing: 8) {
							Text(row.agentName)
								.fontWeight(.medium)
								.lineLimit(1)
								.textSelection(.enabled)
							Spacer(minLength: 8)
							HomerCostAmount(row.usd)
							// The usage bars' "42%", not the locale's percent format.
							Text(verbatim: "\(Int((share * 100).rounded()))%")
								.scaledFont(.caption)
								.foregroundStyle(.secondary)
								.monospacedDigit()
								.frame(minWidth: 34, alignment: .trailing)
						}
						HomerCostBar(fraction: share, color: .accentColor, height: 5)
							.accessibilityHidden(true)
					}
					.accessibilityElement(children: .combine)
				}
				Divider()
				HStack(alignment: .firstTextBaseline) {
					Text("Total")
					Spacer()
					HomerCostAmount(totalUsd)
				}
				.fontWeight(.semibold)
			}
		}
	}
}
