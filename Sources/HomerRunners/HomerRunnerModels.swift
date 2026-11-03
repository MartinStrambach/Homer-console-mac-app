import Foundation
import HomerCore

// Mirrors of the Runners page's JSON (`RunnersStatusResponse`, `RunnerQueueStatusResponse` in
// `console/types/homer.ts`; `models/RunnerStatus.kt` on the server). Decoded leniently like the
// other models: a missing list is empty and unknown fields are ignored. What names a row (an
// alias, an instance's id) and the counts the page is about are required, so a 200 that is not
// Homer's JSON still fails to decode.

/// Every configured runner (`GET /api/v1/runners`), with the live instances of the `external`
/// ones.
public nonisolated struct HomerRunners: Equatable, Sendable, Decodable {
	public var runners: [HomerRunner]

	public init(runners: [HomerRunner]) {
		self.runners = runners
	}

	/// The external runners' registered instances, each with its runner's alias as its domain,
	/// as the console's `ExternalInstancesCard` lists them.
	public var externalInstances: [HomerRunnerInstance] {
		runners.filter(\.isExternal).flatMap(\.instances)
	}

	/// Whether any runner is `external`: only then does the page show the instances' card.
	public var hasExternalRunners: Bool {
		runners.contains(where: \.isExternal)
	}
}

/// One configured runner (`RunnerStatus`): `local`, `ssh`, `kubernetes` or `external`.
public nonisolated struct HomerRunner: Equatable, Sendable, Decodable, Identifiable {
	public var alias: String
	/// `local`, `ssh`, `kubernetes` or `external`; a newer server's kind shows as it is sent.
	public var kind: String
	/// Sorted. Always empty for an external runner: its instances carry the tags.
	public var tags: [String]
	/// How many runs it takes at once; nil is unbounded, and always nil for an external runner.
	public var concurrency: Int?
	/// Permits held; for an external runner, its instances' active sessions summed.
	public var inUse: Int
	/// An external runner's registered instances, `domain` set to this runner's alias.
	public var instances: [HomerRunnerInstance]

	public init(
		alias: String,
		kind: String,
		tags: [String] = [],
		concurrency: Int? = nil,
		inUse: Int = 0,
		instances: [HomerRunnerInstance] = []
	) {
		self.alias = alias
		self.kind = kind
		self.tags = tags
		self.concurrency = concurrency
		self.inUse = inUse
		self.instances = instances.map { $0.inDomain(alias) }
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let alias = try container.decode(String.self, forKey: .alias)
		self.alias = alias
		kind = try container.decode(String.self, forKey: .kind)
		tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
		concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency)
		inUse = try container.decode(Int.self, forKey: .inUse)
		let instances = try container.decodeIfPresent([HomerRunnerInstance].self, forKey: .instances) ?? []
		self.instances = instances.map { $0.inDomain(alias) }
	}

	private enum CodingKeys: String, CodingKey {
		case alias, kind, tags, concurrency, inUse, instances
	}

	public var id: String {
		alias
	}

	public var isExternal: Bool {
		kind == "external"
	}

	/// The console's "In use / concurrency" cell: `2 / 4`, `1 / unbounded`, or `3 active` for an
	/// external runner, whose capacity is its instances'.
	public var capacityText: String {
		isExternal ? "\(inUse) active" : HomerRunnerFormat.capacity(inUse: inUse, concurrency: concurrency)
	}

	/// How full it is, 0…1; nil when it is unbounded or external.
	public var load: Double? {
		guard !isExternal, let concurrency, concurrency > 0 else {
			return nil
		}
		return min(1, Double(inUse) / Double(concurrency))
	}
}

/// One live instance of an `external` runner (`RunnerInstanceStatus`), registered through the
/// runner protocol.
public nonisolated struct HomerRunnerInstance: Equatable, Sendable, Decodable, Identifiable {
	public var instanceId: String
	public var name: String
	/// The external runner it registered with — its alias. Not in the JSON: the runner holding it
	/// sets it.
	public var domain: String
	/// Sorted.
	public var tags: [String]
	public var concurrency: Int
	public var activeSessions: Int
	/// Its last claim poll or heartbeat, epoch seconds.
	public var lastSeenAt: Double
	public var registeredAt: Double
	/// Unregistered: it takes no new claims, and its sessions run to their end.
	public var draining: Bool

	public init(
		instanceId: String,
		name: String,
		domain: String = "",
		tags: [String] = [],
		concurrency: Int = 1,
		activeSessions: Int = 0,
		lastSeenAt: Double,
		registeredAt: Double,
		draining: Bool = false
	) {
		self.instanceId = instanceId
		self.name = name
		self.domain = domain
		self.tags = tags
		self.concurrency = concurrency
		self.activeSessions = activeSessions
		self.lastSeenAt = lastSeenAt
		self.registeredAt = registeredAt
		self.draining = draining
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		instanceId = try container.decode(String.self, forKey: .instanceId)
		name = try container.decodeIfPresent(String.self, forKey: .name) ?? instanceId
		domain = ""
		tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
		concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? 1
		activeSessions = try container.decodeIfPresent(Int.self, forKey: .activeSessions) ?? 0
		lastSeenAt = try container.decode(Double.self, forKey: .lastSeenAt)
		registeredAt = try container.decode(Double.self, forKey: .registeredAt)
		draining = try container.decodeIfPresent(Bool.self, forKey: .draining) ?? false
	}

	private enum CodingKeys: String, CodingKey {
		case instanceId, name, tags, concurrency, activeSessions, lastSeenAt, registeredAt, draining
	}

	public var id: String {
		"\(domain)/\(instanceId)"
	}

	/// The console's "Sessions / concurrency" cell.
	public var capacityText: String {
		HomerRunnerFormat.capacity(inUse: activeSessions, concurrency: concurrency)
	}

	func inDomain(_ domain: String) -> Self {
		var instance = self
		instance.domain = domain
		return instance
	}
}

/// The runs waiting for a runner to claim them (`GET /api/v1/runners/queue`), grouped by what
/// they wait for.
public nonisolated struct HomerRunnerQueue: Equatable, Sendable, Decodable {
	public var pending: Int
	/// The oldest pending claim's age, seconds; nil when nothing is pending.
	public var oldestAgeSec: Int?
	/// Oldest first.
	public var byFilter: [Group]

	public init(pending: Int, oldestAgeSec: Int? = nil, byFilter: [Group] = []) {
		self.pending = pending
		self.oldestAgeSec = oldestAgeSec
		self.byFilter = byFilter
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		pending = try container.decode(Int.self, forKey: .pending)
		oldestAgeSec = try container.decodeIfPresent(Int.self, forKey: .oldestAgeSec)
		byFilter = try container.decodeIfPresent([Group].self, forKey: .byFilter) ?? []
	}

	private enum CodingKeys: String, CodingKey {
		case pending, oldestAgeSec, byFilter
	}

	/// The pending claims that wait for the same runner, or the same tags (`RunnerQueueGroup`).
	public nonisolated struct Group: Equatable, Sendable, Decodable, Identifiable {
		public var filter: Filter
		public var pending: Int
		public var oldestAgeSec: Int

		public init(filter: Filter, pending: Int, oldestAgeSec: Int) {
			self.filter = filter
			self.pending = pending
			self.oldestAgeSec = oldestAgeSec
		}

		public var id: String {
			filter.description
		}
	}

	/// What a claim waits for (`RunnerFilterView`): a runner by its alias, or any runner with
	/// these tags. The server sets exactly one of the two.
	public nonisolated struct Filter: Equatable, Sendable, Decodable, CustomStringConvertible {
		public var alias: String?
		public var tags: [String]?

		public init(alias: String? = nil, tags: [String]? = nil) {
			self.alias = alias
			self.tags = tags
		}

		/// `runner k8s` or `tags gpu, linux`, the console's `describeFilter`.
		public var description: String {
			if let alias {
				return "runner \(alias)"
			}
			return "tags \((tags ?? []).joined(separator: ", "))"
		}
	}
}

/// The Runners page's text formats, the console's own.
nonisolated enum HomerRunnerFormat {
	/// `2 / 4`, or `1 / unbounded` with no concurrency.
	static func capacity(inUse: Int, concurrency: Int?) -> String {
		"\(inUse) / \(concurrency.map(String.init) ?? "unbounded")"
	}

	/// `45s`, `2m 5s`, `1h 2m 5s`: how long the oldest claim has waited. The console writes
	/// `3725 s`; a claim stuck for an hour reads better as hours.
	static func age(seconds: Int) -> String {
		HomerFormat.duration(from: 0, to: Double(seconds))
	}
}
