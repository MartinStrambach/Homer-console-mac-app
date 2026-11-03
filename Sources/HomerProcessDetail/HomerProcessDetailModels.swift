import Foundation
import HomerCore

// The process page's part of the API (`console/types/homer.ts`): a run's artifacts. The live tail
// of a command's output is `HomerCore`'s, its LangGraph workflow status `HomerWorkflowGraph`'s.

/// A file in a run's artifacts directory (`GET /api/v1/artifacts/list`).
public nonisolated struct HomerArtifact: Equatable, Sendable, Identifiable, Decodable {
	/// Relative to the artifacts directory — what the artifact calls take.
	public var path: String
	public var size: Int
	/// Epoch seconds.
	public var modified: Double

	public init(path: String, size: Int, modified: Double) {
		self.path = path
		self.size = size
		self.modified = modified
	}

	public var id: String {
		path
	}
}

nonisolated struct HomerArtifactListing: Decodable {
	var files: [HomerArtifact]
}

/// An artifact's content as `GET /api/v1/artifacts` serves it.
public nonisolated struct HomerArtifactContent: Equatable, Sendable {
	public var text: String
	/// The file's length in bytes when it was read — where the live tail resumes.
	public var byteCount: Int
	/// `X-File-Complete`: false while the command is still writing the file.
	public var isComplete: Bool

	public init(text: String, byteCount: Int, isComplete: Bool) {
		self.text = text
		self.byteCount = byteCount
		self.isComplete = isComplete
	}
}

public nonisolated enum HomerArtifactPath {
	/// The `path` the artifact calls take (`toArtifactApiPath`): an execution's absolute
	/// `stdOut`/`stdErr` is cut to its file name — command output lies flat in the artifacts
	/// directory — and a relative path (from the artifact list) stays as it is, sub-directory
	/// and all.
	public static func apiPath(_ path: String) -> String {
		path.hasPrefix("/") ? fileName(path) : path
	}

	public static func fileName(_ path: String) -> String {
		path.split(separator: "/").last.map(String.init) ?? "artifact"
	}

	/// The running command's output files, which no execution names yet.
	public static func liveOutput(executionIndex: Int, stream: HomerOutputStream) -> String {
		"cmd_\(executionIndex).\(stream == .stdout ? "out" : "err")"
	}
}

/// A message an operator sent a running run (`RunMessage`, Homer 1.38, ADR-0097): the run reads
/// its inbox at its next check — a Claude hook, the `check_messages` MCP tool or `homer-inbox`.
public nonisolated struct HomerRunMessage: Equatable, Sendable, Identifiable, Decodable {
	public nonisolated enum Status: String, Equatable, Sendable, Decodable {
		/// Waiting for the run to take it.
		case queued = "QUEUED"
		case delivered = "DELIVERED"
		/// The run ended before it took it.
		case undelivered = "UNDELIVERED"
		case unknown

		public init(from decoder: any Decoder) throws {
			let raw = try decoder.singleValueContainer().decode(String.self)
			self = Self(rawValue: raw.uppercased()) ?? .unknown
		}
	}

	public var id: String
	public var processId: Int
	/// The operator's free text, shown as plain text.
	public var text: String
	public var status: Status
	/// Who sent it, e.g. `session:admin`.
	public var sender: String?
	public var createdAt: Double
	public var deliveredAt: Double?

	public init(
		id: String,
		processId: Int,
		text: String,
		status: Status,
		sender: String? = nil,
		createdAt: Double,
		deliveredAt: Double? = nil
	) {
		self.id = id
		self.processId = processId
		self.text = text
		self.status = status
		self.sender = sender
		self.createdAt = createdAt
		self.deliveredAt = deliveredAt
	}
}

/// `GET /api/v1/status/{id}/messages`: the run's inbox, oldest first.
nonisolated struct HomerRunMessageList: Decodable {
	var messages: [HomerRunMessage]
}
