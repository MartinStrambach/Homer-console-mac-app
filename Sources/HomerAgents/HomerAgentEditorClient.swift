import ComposableArchitecture
import Foundation
import HomerCore

/// The agent editor's part of the Homer API, addressed by the instance's base URL. Errors are
/// `HomerAPIError`s.
@DependencyClient
public struct HomerAgentEditorClient: Sendable {
	/// The agent directory's files and directories, flat, with relative paths.
	public var files: @Sendable (_ baseURL: String, _ agentName: String) async throws -> [HomerAgentFile]
	public var file: @Sendable (_ baseURL: String, _ agentName: String, _ path: String) async throws -> String
	public var saveFile: @Sendable (_ baseURL: String, _ agentName: String, _ path: String, _ content: String) async throws -> Void
	public var deleteFile: @Sendable (_ baseURL: String, _ agentName: String, _ path: String) async throws -> Void
	/// Starts a debug run of one command and returns its process id.
	public var debug: @Sendable (_ baseURL: String, _ agentName: String, _ request: HomerAgentDebugRequest) async throws -> Int
	/// Tails a command's output from a byte offset on.
	public var logEvents: @Sendable (
		_ baseURL: String,
		_ processId: Int,
		_ commandIndex: Int,
		_ stream: HomerOutputStream,
		_ offset: Int
	) -> AsyncThrowingStream<HomerLogEvent, any Error> = { _, _, _, _, _ in .finished() }
}

extension HomerAgentEditorClient: DependencyKey {
	public static let liveValue = HomerAgentEditorClient(
		files: { try await HomerAPI.agentFiles(baseURL: $0, agentName: $1) },
		file: { try await HomerAPI.agentFile(baseURL: $0, agentName: $1, path: $2) },
		saveFile: { try await HomerAPI.saveAgentFile(baseURL: $0, agentName: $1, path: $2, content: $3) },
		deleteFile: { try await HomerAPI.deleteAgentFile(baseURL: $0, agentName: $1, path: $2) },
		debug: { try await HomerAPI.debugAgentCommand(baseURL: $0, agentName: $1, request: $2) },
		logEvents: {
			HomerAPI.logEvents(baseURL: $0, processId: $1, executionIndex: $2, stream: $3, offset: $4)
		}
	)
}

extension HomerAgentEditorClient: TestDependencyKey {
	public static let testValue = HomerAgentEditorClient()
}
