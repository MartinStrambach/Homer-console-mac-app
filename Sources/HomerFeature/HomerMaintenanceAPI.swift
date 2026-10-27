import Foundation
import HomerCore

/// The admin maintenance-mode toggle (`GET`/`POST /api/v1/maintenance`, Homer 1.36, ADR-0092).
/// The server answers anyone but an admin with a body-less 404, the same as a server that
/// predates the endpoint, so a 404 is told in those words.
extension HomerAPI {
	static func maintenance(baseURL: String) async throws -> HomerMaintenance {
		try await maintenanceCall { try await send("GET", "/api/v1/maintenance", baseURL: baseURL) }
	}

	static func setMaintenance(baseURL: String, enabled: Bool) async throws -> HomerMaintenance {
		let body = try JSONEncoder().encode(["enabled": enabled])
		return try await maintenanceCall {
			try await send("POST", "/api/v1/maintenance", baseURL: baseURL, body: body)
		}
	}

	private static func maintenanceCall(_ call: () async throws -> Data) async throws -> HomerMaintenance {
		do {
			return try await decode(HomerMaintenance.self, from: call())
		}
		catch HomerAPIError.server(status: 404, _) {
			throw HomerAPIError.server(
				status: 404,
				message: "The server has no maintenance mode for this account: it needs Homer 1.36 or later, and an admin."
			)
		}
	}
}

/// `MaintenanceResponse`: the mode, when it was turned on and how many starts wait for it to end.
public nonisolated struct HomerMaintenance: Equatable, Sendable, Decodable {
	public var enabled: Bool
	/// Epoch seconds it was turned on; nil while off, and for a mode already on when the server
	/// started (the server does not keep the time across a restart).
	public var since: Double?
	/// Starts waiting in the queue right now.
	public var queued: Int

	public init(enabled: Bool, since: Double? = nil, queued: Int = 0) {
		self.enabled = enabled
		self.since = since
		self.queued = queued
	}

	private enum CodingKeys: String, CodingKey {
		case enabled, since, queued
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		enabled = try container.decode(Bool.self, forKey: .enabled)
		since = try container.decodeIfPresent(Double.self, forKey: .since)
		queued = try container.decodeIfPresent(Int.self, forKey: .queued) ?? 0
	}
}
