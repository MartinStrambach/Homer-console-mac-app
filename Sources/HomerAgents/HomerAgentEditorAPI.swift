import Foundation
import HomerCore

/// The agent editor's calls (`listAgentFiles`, `readAgentFile`, `writeAgentFile`,
/// `deleteAgentFile` and `debugAgentCommand` in the console's `lib/api/client.ts`). Every file
/// call needs an `edit` grant on the agent, a debug run a `debug` grant.
extension HomerAPI {
	static func agentFiles(baseURL: String, agentName: String) async throws -> [HomerAgentFile] {
		try await decode(
			HomerAgentFileList.self,
			from: send("GET", agentFilesPath(agentName: agentName), baseURL: baseURL, refusalsInServerWords: true)
		).entries
	}

	static func agentFile(baseURL: String, agentName: String, path: String) async throws -> String {
		try await decode(
			HomerAgentFileContent.self,
			from: send("GET", agentFilePath(agentName: agentName, path: path), baseURL: baseURL, refusalsInServerWords: true)
		).content
	}

	/// Writes the file, creating it (and its directories) if need be. A definition the server's
	/// schema refuses is a 422 with the reasons (`HomerAPIError.invalid`); the file is left as it
	/// was.
	static func saveAgentFile(baseURL: String, agentName: String, path: String, content: String) async throws {
		_ = try await send(
			"PUT",
			agentFilePath(agentName: agentName, path: path),
			baseURL: baseURL,
			body: JSONEncoder().encode(["content": content]),
			refusalsInServerWords: true
		)
	}

	static func deleteAgentFile(baseURL: String, agentName: String, path: String) async throws {
		_ = try await send(
			"DELETE",
			agentFilePath(agentName: agentName, path: path),
			baseURL: baseURL,
			refusalsInServerWords: true
		)
	}

	/// Starts one command of the agent as a real run (its locks and parallel-run slots, but no
	/// cost cap) and returns the run's id. A refusal (409 a lock, 429 the cooldown) is told in
	/// the server's words.
	static func debugAgentCommand(baseURL: String, agentName: String, request: HomerAgentDebugRequest) async throws -> Int {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let data = try await send(
			"POST",
			"/api/v1/agents/" + HomerAgent.encodeURIComponent(agentName) + "/debug",
			baseURL: baseURL,
			body: encoder.encode(request),
			refusalsInServerWords: true
		)
		return try decode(HomerAgentRunResponse.self, from: data).processId
	}

	static func agentFilesPath(agentName: String) -> String {
		"/api/v1/agents/" + HomerAgent.encodeURIComponent(agentName) + "/files"
	}

	/// Each segment of the relative path encoded on its own, so the slashes stay separators.
	static func agentFilePath(agentName: String, path: String) -> String {
		let segments = path.split(separator: "/", omittingEmptySubsequences: false)
			.map { HomerAgent.encodeURIComponent(String($0)) }
		return agentFilesPath(agentName: agentName) + "/" + segments.joined(separator: "/")
	}
}
