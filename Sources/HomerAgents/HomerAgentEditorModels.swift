import Foundation
import HomerCore

// Mirrors of the agent file and debug calls (`AgentFileEntry`, `AgentFileListResponse`,
// `AgentFileContentResponse`, `DebugAgentRequest` in the console's `types/homer.ts`) and the
// key/value rows of its debug dialog (`lib/utils/kv.ts`).

/// A file or directory in an agent's directory (`GET /api/v1/agents/{name}/files`), listed flat
/// with paths relative to the directory.
public nonisolated struct HomerAgentFile: Equatable, Sendable, Identifiable, Decodable {
	public var path: String
	public var size: Int
	/// Epoch seconds.
	public var mtime: Double
	public var isDirectory: Bool

	public init(path: String, size: Int = 0, mtime: Double = 0, isDirectory: Bool = false) {
		self.path = path
		self.size = size
		self.mtime = mtime
		self.isDirectory = isDirectory
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		path = try container.decode(String.self, forKey: .path)
		size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
		mtime = try container.decodeIfPresent(Double.self, forKey: .mtime) ?? 0
		isDirectory = try container.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false
	}

	private enum CodingKeys: String, CodingKey {
		case path, size, mtime, isDirectory
	}

	public var id: String {
		path
	}

	/// The agent's definition, which the editor opens first and never offers to delete.
	public var isDefinition: Bool {
		Self.definitionPaths.contains(path)
	}

	/// The definition files the editor opens first, in the order it looks for them.
	static let definitionPaths = ["agent.yaml", "agent.json"]

	/// The console's file tree order (`file-tree.tsx`): directories first, then by path.
	public static func sorted(_ files: some Sequence<HomerAgentFile>) -> [HomerAgentFile] {
		files.sorted { lhs, rhs in
			if lhs.isDirectory != rhs.isDirectory {
				return lhs.isDirectory
			}
			return lhs.path.localizedCompare(rhs.path) == .orderedAscending
		}
	}
}

nonisolated struct HomerAgentFileList: Decodable {
	var entries: [HomerAgentFile]
}

nonisolated struct HomerAgentFileContent: Decodable {
	var content: String
}

/// One row of the debug dialog's query params or environment (`KV`). The id keeps a row's
/// fields in place while its key is edited.
public nonisolated struct HomerKeyValue: Equatable, Sendable, Identifiable {
	public let id: UUID
	public var key: String
	public var value: String

	public init(id: UUID, key: String = "", value: String = "") {
		self.id = id
		self.key = key
		self.value = value
	}

	/// `kvListToRecord`: trimmed keys, empty ones skipped, a later row winning over an earlier
	/// one of the same key.
	public static func record(_ rows: [HomerKeyValue]) -> [String: String] {
		var record: [String: String] = [:]
		for row in rows {
			let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
			if !key.isEmpty {
				record[key] = row.value
			}
		}
		return record
	}
}

/// What `POST /api/v1/agents/{name}/debug` runs: one declared command, with query params run
/// through the agent's transformers and environment variables merged in as they are.
public nonisolated struct HomerAgentDebugRequest: Equatable, Sendable, Encodable {
	public var commandIndex: Int
	public var env: [String: String]
	public var queryParams: [String: String]

	public init(commandIndex: Int, env: [String: String] = [:], queryParams: [String: String] = [:]) {
		self.commandIndex = commandIndex
		self.env = env
		self.queryParams = queryParams
	}

	public init(commandIndex: Int, env: [HomerKeyValue], params: [HomerKeyValue]) {
		self.init(
			commandIndex: commandIndex,
			env: HomerKeyValue.record(env),
			queryParams: HomerKeyValue.record(params)
		)
	}
}

/// The editor's syntax: the console's `languageFor` (`agent-file-editor.tsx`), by extension.
public nonisolated enum HomerAgentFileLanguage: Equatable, Sendable {
	case json
	case yaml
	case markdown
	case shell
	case javascript
	case typescript
	case python
	case plaintext

	public init(path: String) {
		let lower = path.lowercased()
		self = if lower.hasSuffix(".json") {
			.json
		}
		else if lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
			.yaml
		}
		else if lower.hasSuffix(".md") {
			.markdown
		}
		else if lower.hasSuffix(".sh") || lower.hasSuffix(".bash") {
			.shell
		}
		else if lower.hasSuffix(".js") || lower.hasSuffix(".mjs") {
			.javascript
		}
		else if lower.hasSuffix(".ts") {
			.typescript
		}
		else if lower.hasSuffix(".py") {
			.python
		}
		else {
			.plaintext
		}
	}
}
