import Foundation
import HomerCore

/// The Runners page's calls (`getRunners`, `getRunnerQueue` in `console/lib/api/client.ts`).
/// Both need the admin role; anyone else gets a 403.
extension HomerAPI {
	static func runners(baseURL: String) async throws -> HomerRunners {
		try await decode(HomerRunners.self, from: send("GET", "/api/v1/runners", baseURL: baseURL))
	}

	static func runnerQueue(baseURL: String) async throws -> HomerRunnerQueue {
		try await decode(HomerRunnerQueue.self, from: send("GET", "/api/v1/runners/queue", baseURL: baseURL))
	}
}
