import Foundation

/// `GET /api/v1/health` (`HealthResponse`): the instance's runners and the orphan pod sweep it
/// last ran at startup. A status page for people, not a probe — it does not turn 503 while the
/// server drains.
public nonisolated struct HomerHealth: Equatable, Sendable, Decodable {
	public nonisolated struct Runner: Equatable, Sendable, Decodable {
		public var alias: String
		/// `local`, `ssh` or `kubernetes`.
		public var type: String

		public init(alias: String, type: String) {
			self.alias = alias
			self.type = type
		}
	}

	/// The startup sweep of Kubernetes pods no run owns any more (`SweepStatus`).
	public nonisolated struct Sweep: Equatable, Sendable, Decodable {
		public nonisolated struct DeletedPod: Equatable, Sendable, Decodable {
			public var namespace: String
			public var name: String
			public var processId: Int?
			public var runnerAlias: String?

			public init(namespace: String, name: String, processId: Int? = nil, runnerAlias: String? = nil) {
				self.namespace = namespace
				self.name = name
				self.processId = processId
				self.runnerAlias = runnerAlias
			}
		}

		public var ranAt: Double
		public var scanned: Int
		public var deleted: [DeletedPod]
		public var errors: [String]

		public init(ranAt: Double, scanned: Int, deleted: [DeletedPod] = [], errors: [String] = []) {
			self.ranAt = ranAt
			self.scanned = scanned
			self.deleted = deleted
			self.errors = errors
		}
	}

	public var runners: [Runner]
	public var sweep: Sweep?

	public init(runners: [Runner], sweep: Sweep? = nil) {
		self.runners = runners
		self.sweep = sweep
	}

	/// The sweep worth showing: the console's banner is there only with a Kubernetes runner,
	/// the one kind of runner that leaves pods behind.
	public var kubernetesSweep: Sweep? {
		runners.contains { $0.type == "kubernetes" } ? sweep : nil
	}
}

/// `GET /api/v1/heartbeat`: `version` is the server's `HOMER_VERSION`, `dev` when unset.
nonisolated struct HomerHeartbeat: Decodable {
	var version: String?
}
