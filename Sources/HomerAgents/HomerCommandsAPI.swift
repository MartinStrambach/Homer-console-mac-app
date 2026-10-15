import Foundation
import HomerCore

/// The command bar's call. Homer serves its Slack connector's commands from the connector's
/// `config.yaml`, filtered to the agents the user may run.
extension HomerAPI {
	/// nil when the server predates `GET /api/v1/commands` (404); an empty list when it has no
	/// connector configured.
	static func commands(baseURL: String) async throws -> HomerCommandList? {
		do {
			return try await decode(HomerCommandList.self, from: send("GET", "/api/v1/commands", baseURL: baseURL))
		}
		catch HomerAPIError.server(status: 404, _) {
			return nil
		}
	}
}
