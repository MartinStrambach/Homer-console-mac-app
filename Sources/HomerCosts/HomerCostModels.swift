import Foundation
import HomerCore

// Mirrors of the Costs page's JSON (`CostsResponse`, `MonthlyCostsResponse`, `TotalCostsResponse`
// in `console/types/homer.ts`; `models/ServerStatus.kt` on the server). Decoded leniently like
// the other models: a missing map is empty and unknown fields are ignored. The one figure each
// answer is about is required, so a 200 that is not Homer's JSON still fails to decode.

/// The server's `CostMeter` right now (`GET /api/v1/costs`): Claude spend over the rolling
/// windows its caps are checked against, with the caps configured.
public nonisolated struct HomerCostSnapshot: Equatable, Sendable, Decodable {
	/// Spend of the last 60 s across every agent.
	public var globalUsdLast60s: Double
	/// The cap on `globalUsdLast60s`; nil when none is configured.
	public var globalCapUsdPerMin: Double?
	/// Each agent's spend of the last 24 h.
	public var perAgentUsdLast24h: [String: Double]
	/// Each capped agent's cap on its 24 h spend. Agents not listed are uncapped.
	public var perAgentCapUsdPerDay: [String: Double]
	/// When the server took the snapshot, in epoch seconds.
	public var snapshotAtSec: Double?
	/// The tag keys whose spend the server sums per value (`costTrackedTagKeys` in its config),
	/// in the config's order — each one a choice of the "Cost by tag" card.
	public var costTrackedTagKeys: [String]

	public init(
		globalUsdLast60s: Double,
		globalCapUsdPerMin: Double? = nil,
		perAgentUsdLast24h: [String: Double] = [:],
		perAgentCapUsdPerDay: [String: Double] = [:],
		snapshotAtSec: Double? = nil,
		costTrackedTagKeys: [String] = []
	) {
		self.globalUsdLast60s = globalUsdLast60s
		self.globalCapUsdPerMin = globalCapUsdPerMin
		self.perAgentUsdLast24h = perAgentUsdLast24h
		self.perAgentCapUsdPerDay = perAgentCapUsdPerDay
		self.snapshotAtSec = snapshotAtSec
		self.costTrackedTagKeys = costTrackedTagKeys
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		globalUsdLast60s = try container.decode(Double.self, forKey: .globalUsdLast60s)
		globalCapUsdPerMin = try container.decodeIfPresent(Double.self, forKey: .globalCapUsdPerMin)
		perAgentUsdLast24h = try container.decodeIfPresent([String: Double].self, forKey: .perAgentUsdLast24h) ?? [:]
		perAgentCapUsdPerDay = try container.decodeIfPresent([String: Double].self, forKey: .perAgentCapUsdPerDay) ?? [:]
		snapshotAtSec = try container.decodeIfPresent(Double.self, forKey: .snapshotAtSec)
		costTrackedTagKeys = try container.decodeIfPresent([String].self, forKey: .costTrackedTagKeys) ?? []
	}

	private enum CodingKeys: String, CodingKey {
		case globalUsdLast60s, globalCapUsdPerMin, perAgentUsdLast24h, perAgentCapUsdPerDay, snapshotAtSec
		case costTrackedTagKeys
	}

	/// One agent's row of the per-agent table: its 24 h spend against its cap.
	public nonisolated struct AgentUsage: Equatable, Sendable, Identifiable {
		public var agentName: String
		public var spentUsd: Double
		public var capUsd: Double?

		public var id: String {
			agentName
		}
	}

	/// Every agent that has spent or has a cap, sorted by name — an agent with a cap and no
	/// spend yet is listed at $0, as in the console's `PerAgentTable`.
	public var agentUsages: [AgentUsage] {
		Set(perAgentUsdLast24h.keys).union(perAgentCapUsdPerDay.keys).sorted().map { agentName in
			AgentUsage(
				agentName: agentName,
				spentUsd: perAgentUsdLast24h[agentName] ?? 0,
				capUsd: perAgentCapUsdPerDay[agentName]
			)
		}
	}
}

/// One row of a breakdown table: an agent's spend in a ledger (a month's, or all time), or a
/// tag value's in the cost by tag.
public nonisolated struct HomerCostRow: Equatable, Sendable, Identifiable {
	/// The agent, or the tag value.
	public var name: String
	public var usd: Double

	public init(name: String, usd: Double) {
		self.name = name
		self.usd = usd
	}

	public var id: String {
		name
	}

	/// The rows of a name → spend map, sorted by name as the console lists them.
	static func rows(_ usdByName: [String: Double]) -> [Self] {
		usdByName.keys.sorted().map { Self(name: $0, usd: usdByName[$0] ?? 0) }
	}
}

/// One UTC month of the persistent cost ledger (`GET /api/v1/costs/monthly?month=YYYY-MM`).
public nonisolated struct HomerMonthlyCosts: Equatable, Sendable, Decodable {
	/// `YYYY-MM`, UTC. The server's current month when none was asked for.
	public var month: String
	public var perAgentUsd: [String: Double]
	public var totalUsd: Double
	/// The months with at least one entry, newest first.
	public var availableMonths: [String]

	public init(month: String, perAgentUsd: [String: Double] = [:], totalUsd: Double, availableMonths: [String] = []) {
		self.month = month
		self.perAgentUsd = perAgentUsd
		self.totalUsd = totalUsd
		self.availableMonths = availableMonths
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		month = try container.decode(String.self, forKey: .month)
		perAgentUsd = try container.decodeIfPresent([String: Double].self, forKey: .perAgentUsd) ?? [:]
		totalUsd = try container.decode(Double.self, forKey: .totalUsd)
		availableMonths = try container.decodeIfPresent([String].self, forKey: .availableMonths) ?? []
	}

	private enum CodingKeys: String, CodingKey {
		case month, perAgentUsd, totalUsd, availableMonths
	}

	public var rows: [HomerCostRow] {
		HomerCostRow.rows(perAgentUsd)
	}

	/// The month picker's choices, newest first: the months with entries plus the one shown,
	/// which may have none yet (a fresh current month) — the console adds it the same way.
	public var pickerMonths: [String] {
		Set(availableMonths).union([month]).sorted(by: >)
	}
}

/// All-time spend from the persistent cost ledger (`GET /api/v1/costs/totals`).
public nonisolated struct HomerTotalCosts: Equatable, Sendable, Decodable {
	public var perAgentUsd: [String: Double]
	public var totalUsd: Double

	public init(perAgentUsd: [String: Double] = [:], totalUsd: Double) {
		self.perAgentUsd = perAgentUsd
		self.totalUsd = totalUsd
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		perAgentUsd = try container.decodeIfPresent([String: Double].self, forKey: .perAgentUsd) ?? [:]
		totalUsd = try container.decode(Double.self, forKey: .totalUsd)
	}

	private enum CodingKeys: String, CodingKey {
		case perAgentUsd, totalUsd
	}

	public var rows: [HomerCostRow] {
		HomerCostRow.rows(perAgentUsd)
	}
}

/// The spend per value of one cost-tracked tag key (`GET /api/v1/costs/by-tag/{key}`), e.g.
/// each ticket's under `ticket_id`.
public nonisolated struct HomerCostByTag: Equatable, Sendable, Decodable {
	public var key: String
	public var valuesUsd: [String: Double]
	public var totalUsd: Double
	/// More runs carried the tag than the server sums (its newest 10,000), so the figures are
	/// short of the whole.
	public var truncated: Bool

	public init(key: String, valuesUsd: [String: Double] = [:], totalUsd: Double, truncated: Bool = false) {
		self.key = key
		self.valuesUsd = valuesUsd
		self.totalUsd = totalUsd
		self.truncated = truncated
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		key = try container.decode(String.self, forKey: .key)
		valuesUsd = try container.decodeIfPresent([String: Double].self, forKey: .valuesUsd) ?? [:]
		totalUsd = try container.decode(Double.self, forKey: .totalUsd)
		truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
	}

	private enum CodingKeys: String, CodingKey {
		case key, valuesUsd, totalUsd, truncated
	}

	public var rows: [HomerCostRow] {
		HomerCostRow.rows(valuesUsd)
	}
}

/// Spend against a cap, as the console's `CostUsageBar` draws it: the bar fills up to 100 %,
/// turns yellow from 80 % and red at the cap.
public nonisolated struct HomerCostUsage: Equatable, Sendable {
	public enum Level: Equatable, Sendable {
		case normal
		case nearCap
		case overCap
	}

	public var spentUsd: Double
	public var capUsd: Double

	public init(spentUsd: Double, capUsd: Double) {
		self.spentUsd = spentUsd
		self.capUsd = capUsd
	}

	/// Spend over cap; 0 for a cap of 0, which the server does not allow anyway.
	public var ratio: Double {
		capUsd > 0 ? spentUsd / capUsd : 0
	}

	/// How full the bar is, 0…100.
	public var percent: Double {
		min(100, max(0, ratio * 100))
	}

	public var level: Level {
		if ratio >= 1 {
			.overCap
		}
		else if ratio >= 0.8 {
			.nearCap
		}
		else {
			.normal
		}
	}

	/// `25%`, rounded half up like the console's `toFixed(0)`.
	public var percentText: String {
		"\(Int(percent.rounded()))%"
	}
}
