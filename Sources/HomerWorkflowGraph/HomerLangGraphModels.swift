import Foundation
import HomerCore

// A run's LangGraph workflow: its status and topology (`console/types/homer.ts`).

/// A run's LangGraph workflow (`LangGraphRunStatus`, `GET /api/v1/processes/{id}/langgraph`).
/// Without `?graph=true` only the identifying fields are sent — the probe that tells whether the
/// run has a workflow at all (404 when it has none) and which of its commands runs it.
public nonisolated struct HomerLangGraphStatus: Equatable, Sendable, Decodable {
	/// A sub-agent run a parked node dispatched (`LangGraphSubProgress`).
	public nonisolated struct Sub: Equatable, Sendable, Decodable {
		/// One command of the sub run: `ok`, `failed`, `skipped` or `running`.
		public nonisolated struct Command: Equatable, Sendable, Decodable {
			public var label: String
			public var state: String

			public init(label: String, state: String) {
				self.label = label
				self.state = state
			}
		}

		public var interruptId: String
		public var processId: Int?
		public var agentName: String?
		/// The sub run's process status; nil once the run left the process store.
		public var status: String?
		public var commands: [Command]?

		public init(
			interruptId: String,
			processId: Int? = nil,
			agentName: String? = nil,
			status: String? = nil,
			commands: [Command]? = nil
		) {
			self.interruptId = interruptId
			self.processId = processId
			self.agentName = agentName
			self.status = status
			self.commands = commands
		}
	}

	/// A node and its state, in graph order.
	public nonisolated struct Node: Equatable, Sendable {
		public var name: String
		/// `done`, `failed`, `parked` or `pending`; anything else is shown as sent.
		public var state: String

		public init(name: String, state: String) {
			self.name = name
			self.state = state
		}
	}

	/// The workflow's graph (`LangGraphTopology`, ADR-0073): its nodes in the order the graph
	/// added them, `__start__` and `__end__` included, and its edges.
	public nonisolated struct Topology: Equatable, Hashable, Sendable, Decodable {
		public nonisolated struct Node: Equatable, Hashable, Sendable, Decodable {
			public var id: String

			public init(id: String) {
				self.id = id
			}
		}

		/// `add_edge` (always taken) or, `conditional`, one of a router's targets.
		public nonisolated struct Edge: Equatable, Hashable, Sendable, Decodable {
			public var source: String
			public var target: String
			public var label: String?
			public var conditional: Bool

			public init(source: String, target: String, label: String? = nil, conditional: Bool = false) {
				self.source = source
				self.target = target
				self.label = label
				self.conditional = conditional
			}

			public init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				source = try container.decode(String.self, forKey: .source)
				target = try container.decode(String.self, forKey: .target)
				label = try container.decodeIfPresent(String.self, forKey: .label)
				conditional = try container.decodeIfPresent(Bool.self, forKey: .conditional) ?? false
			}

			private enum CodingKeys: String, CodingKey {
				case source, target, label, conditional
			}
		}

		public var nodes: [Node]
		public var edges: [Edge]

		public init(nodes: [Node], edges: [Edge] = []) {
			self.nodes = nodes
			self.edges = edges
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			nodes = try container.decode([Node].self, forKey: .nodes)
			edges = try container.decodeIfPresent([Edge].self, forKey: .edges) ?? []
		}

		private enum CodingKeys: String, CodingKey {
			case nodes, edges
		}
	}

	/// An edge of the topology the run has taken (`LangGraphEdgeRef`, ADR-0075).
	public nonisolated struct Edge: Equatable, Sendable, Decodable {
		public var source: String
		public var target: String

		public init(source: String, target: String) {
			self.source = source
			self.target = target
		}
	}

	/// The command whose run is the workflow — the execution the status belongs to.
	public var label: String
	public var module: String?
	public var threadId: String
	/// Sent since Homer 1.28 with `graph=true`; absent from an older `homer_langgraph` runtime's
	/// state.
	public var topology: Topology?
	/// Deprecated by `topology` (Homer 1.28) and gone from the console's types; read only to
	/// order the nodes of a server or runtime that sends no topology.
	public var mermaid: String?
	/// Each node's state, by name. JSON objects carry no order a `Dictionary` keeps; `nodes`
	/// puts them in graph order.
	public var nodeStates: [String: String]?
	public var errors: [String: String]?
	public var subs: [String: [Sub]]?
	/// Nodes whose interrupt history hit the runtime's cap: their oldest subs are missing.
	public var subsTruncated: [String]?
	/// The edges the run has taken (Homer 1.29), or nil when unknown — the console draws them
	/// green.
	public var traversed: [Edge]?
	/// Why the status could not be read. The other fields are then unreliable.
	public var error: String?

	public init(
		label: String,
		module: String? = nil,
		threadId: String,
		topology: Topology? = nil,
		mermaid: String? = nil,
		nodeStates: [String: String]? = nil,
		errors: [String: String]? = nil,
		subs: [String: [Sub]]? = nil,
		subsTruncated: [String]? = nil,
		traversed: [Edge]? = nil,
		error: String? = nil
	) {
		self.label = label
		self.module = module
		self.threadId = threadId
		self.topology = topology
		self.mermaid = mermaid
		self.nodeStates = nodeStates
		self.errors = errors
		self.subs = subs
		self.subsTruncated = subsTruncated
		self.traversed = traversed
		self.error = error
	}

	private enum CodingKeys: String, CodingKey {
		case label, module, threadId, topology, mermaid, errors, subs, subsTruncated, traversed, error
		case nodeStates = "nodes"
	}

	/// Whether the web console can draw the workflow's graph.
	public var hasGraph: Bool {
		topology != nil || mermaid != nil
	}

	/// The nodes in the order the graph added them, which is the workflow's own reading order:
	/// the topology's, else the order the Mermaid source declares them (`draw_mermaid` writes
	/// them in that order too). Nodes neither lists (or every node, with neither) follow by
	/// name.
	public var nodes: [Node] {
		guard let nodeStates else {
			return []
		}
		let position: (String) -> Int?
		if let topology {
			let order = Dictionary(
				topology.nodes.enumerated().map { ($0.element.id, $0.offset) },
				uniquingKeysWith: { first, _ in first }
			)
			position = { order[$0] }
		}
		else {
			let order = mermaid.map(Self.declaredNodeIDs(in:)) ?? [:]
			position = { order[Self.mermaidSafeID($0)] }
		}
		return nodeStates
			.map { Node(name: $0.key, state: $0.value) }
			.sorted { lhs, rhs in
				let left = position(lhs.name) ?? .max
				let right = position(rhs.name) ?? .max
				return left != right ? left < right : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
			}
	}

	/// Where the run went from a node: the targets of the taken edges leaving it, in the
	/// server's order.
	public func takenTargets(from node: String) -> [String] {
		(traversed ?? []).filter { $0.source == node }.map(\.target)
	}

	/// Every sub run, node by node in graph order.
	public var allSubs: [(node: String, sub: Sub)] {
		nodes.flatMap { node in (subs?[node.name] ?? []).map { (node.name, $0) } }
	}

	/// A parked node whose sub runs have all finished: its agents' work is done, but the join
	/// has not resolved, so the node itself has not completed (`lgSubDone` in the console).
	public func subsFinished(node: String) -> Bool {
		guard nodeStates?[node] == "parked", let nodeSubs = subs?[node], !nodeSubs.isEmpty else {
			return false
		}
		return nodeSubs.allSatisfy { $0.status == "FINISHED" }
	}

	/// The node ids of a Mermaid flowchart's declaration lines (`\tplan(plan)`,
	/// `\t__start__([<p>__start__</p>]):::first`), by their position.
	static func declaredNodeIDs(in mermaid: String) -> [String: Int] {
		var order: [String: Int] = [:]
		for line in mermaid.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard let open = trimmed.firstIndex(where: { $0 == "(" || $0 == "[" }), open != trimmed.startIndex else {
				continue
			}
			let id = String(trimmed[..<open])
			// Edges (`a --> b;`) hold spaces or arrows before any bracket.
			guard !id.contains(" "), !id.contains("-->"), order[id] == nil else {
				continue
			}
			order[id] = order.count
		}
		return order
	}

	/// The node id `draw_mermaid` writes for a node name (langchain_core's `_to_safe_id`):
	/// characters outside `[a-zA-Z0-9_-]` become a backslash and their lowercase hex code
	/// point.
	static func mermaidSafeID(_ name: String) -> String {
		var id = ""
		for scalar in name.unicodeScalars {
			if scalar.isASCII, scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar) || scalar == "_" || scalar == "-" {
				id.unicodeScalars.append(scalar)
			}
			else {
				id += "\\" + String(scalar.value, radix: 16)
			}
		}
		return id
	}
}
